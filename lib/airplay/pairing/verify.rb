require "openssl"

require "airplay/errors"
require "airplay/plist"
require "airplay/pairing/aead"
require "airplay/pairing/hkdf"
require "airplay/pairing/keys"
require "airplay/pairing/tlv8"

module Airplay
  module Pairing
    # Public: HAP pair-verify client using a stored long-term pairing record.
    class Verify
      IDENTIFIER = 1
      PUBLIC = 3
      ENCRYPTED = 5
      STATE = 6
      ERROR = 7
      SIGNATURE = 10

      attr_reader :shared_secret, :accessory_identifier

      def initialize(record, private_key: nil)
        @record = record
        @private_key = private_key
      end

      # Public: Runs M1-M4 and installs the channel keys on `connection`.
      def run(connection)
        curve = @private_key ? Keys.x25519_private(@private_key) : OpenSSL::PKey.generate_key("X25519")
        public_key = Keys.raw_public(curve)

        first = exchange(connection, { STATE => "\x01".b, PUBLIC => public_key })
        peer_public = tlv(first, PUBLIC)
        @shared_secret = curve.derive(Keys.x25519_public(peer_public))
        encryption_key = HKDF.expand(@shared_secret, salt: "Pair-Verify-Encrypt-Salt",
                                                     info: "Pair-Verify-Encrypt-Info")
        identity = TLV8.decode(
          AEAD.decrypt(key: encryption_key, nonce: AEAD.nonce("PV-Msg02"), ciphertext: tlv(first, ENCRYPTED))
        )
        @accessory_identifier = tlv(identity, IDENTIFIER)

        unless Keys.ed25519_public(bytes("accessory_public"))
                       .verify(nil, tlv(identity, SIGNATURE), peer_public + @accessory_identifier + public_key)
          raise Airplay::AuthFailedError.new("receiver pair-verify signature does not verify", code: :auth_failed)
        end

        signature = Keys.ed25519_private(bytes("client_private"))
                        .sign(nil, public_key + bytes("identifier") + peer_public)
        sealed = AEAD.encrypt(
          key: encryption_key, nonce: AEAD.nonce("PV-Msg03"),
          plaintext: TLV8.encode([
            TLV8::Item.new(IDENTIFIER, bytes("identifier")),
            TLV8::Item.new(SIGNATURE, signature)
          ])
        )
        last = exchange(connection, { STATE => "\x03".b, ENCRYPTED => sealed })
        unless tlv(last, STATE) == "\x04"
          raise Airplay::AuthFailedError.new("receiver did not confirm pair-verify", code: :auth_failed)
        end

        connection.encrypt!(*control_keys)
        self
      end

      def control_keys
        HKDF.control_keys(shared_secret)
      end

      def event_keys
        HKDF.event_keys(shared_secret)
      end

      private

      def exchange(connection, values)
        body = TLV8.encode(values.map { |type, value| TLV8::Item.new(type, value) })
        response = connection.request("POST", "/pair-verify", body: body)
        Unsupported.check!(response.headers["x-airplay-auth"])

        items = TLV8.decode(response.body)
        if tlv(items, ERROR)
          raise Airplay::AuthFailedError.new("pair-verify rejected", code: :auth_failed)
        end

        items
      end

      def tlv(items, type)
        items.find { |item| item.type == type }&.value
      end

      def bytes(field)
        value = @record.fetch(field)
        value.is_a?(Airplay::Plist::Data) ? value.bytes : value.to_s.b
      end
    end
  end
end
