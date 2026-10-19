require "openssl"
require "securerandom"

require "airplay/errors"
require "airplay/status"
require "airplay/pairing/aead"
require "airplay/pairing/credential_store"
require "airplay/pairing/hkdf"
require "airplay/pairing/keys"
require "airplay/pairing/srp"
require "airplay/pairing/tlv8"

module Airplay
  module Pairing
    # Public: HAP pair-setup client: transient (M1-M4) or PIN (M1-M6).
    class Setup
      TRANSIENT_CODE = "3939"
      HEADER = "X-Apple-HKP"
      FLOWS = { "4" => :transient, "3" => :pin }.freeze
      METHOD = 0
      IDENTIFIER = 1
      SALT = 2
      PUBLIC = 3
      PROOF = 4
      ENCRYPTED = 5
      STATE = 6
      ERROR = 7
      SIGNATURE = 10
      ERRORS = {
        0x01 => :connect_failed,    # unknown
        0x02 => :auth_failed,       # authentication
        0x03 => :auth_failed,       # backoff
        0x04 => :connect_failed,    # maximum peers
        0x05 => :auth_failed,       # maximum tries
        0x06 => :connect_failed,    # unavailable
        0x07 => :connect_failed     # busy
      }.freeze

      attr_reader :flow, :key, :identifier, :record

      def self.from_header(value, **options)
        flow = FLOWS[value.to_s]
        unless flow
          raise Airplay::TransportError.new("unsupported pairing flow #{value.inspect}", code: :connect_failed)
        end

        new(**options, transient: flow == :transient)
      end

      def self.pair(device, attempts: 2, **options)
        attempts.times do |attempt|
          begin
            connection = Airplay::Pairing::Connection.new(host: device.host, port: device.port).open
            begin
              return new(**{ device: device.name }.merge(options)).run(connection)
            ensure
              connection.close
            end
          rescue Airplay::AuthFailedError
            raise if attempt + 1 >= attempts
          end
        end
      rescue Airplay::Error => error
        raise error.with_device(device.name)
      end

      def initialize(code: nil, transient: true, store: nil, device: nil)
        if !transient && code.nil?
          raise Airplay::AuthRequiredError.new("a pairing code is required for PIN pairing",
                                               code: :auth_required)
        end

        @code = (code || TRANSIENT_CODE).to_s
        @flow = transient ? :transient : :pin
        @store = store
        @device = device
      end

      def transient?
        flow == :transient
      end

      # Public: Runs the setup exchange over `session` and returns self.
      def run(session)
        Airplay::Status.emit("pairing.setup", flow: flow, device: @device)
        first = exchange(session, { STATE => "\x01".b, METHOD => "\x00".b })
        @srp = SRP.new(pin: @code)
        @srp.process(tlv(first, PUBLIC), tlv(first, SALT))

        second = exchange(session, { STATE => "\x03".b, PUBLIC => padded(@srp.public), PROOF => @srp.proof })
        unless @srp.valid_server_proof?(tlv(second, PROOF))
          raise Airplay::AuthFailedError.new("receiver proof does not verify", code: :auth_failed)
        end

        @key = @srp.key
        complete_identity(session) unless transient?
        Airplay::Status.emit("pairing.ready", flow: flow, transient: transient?)
        self
      rescue Airplay::Error => error
        Airplay::Status.emit("pairing.failed", flow: flow, code: error.code)
        raise
      end

      def control_keys
        HKDF.control_keys(key)
      end

      def event_keys
        HKDF.event_keys(key)
      end

      private

      def complete_identity(session)
        @pair_setup_key = HKDF.expand(key, salt: "Pair-Setup-Encrypt-Salt", info: "Pair-Setup-Encrypt-Info")
        @client_key = OpenSSL::PKey.generate_key("Ed25519")
        client_public = Keys.raw_public(@client_key)
        @identifier = SecureRandom.uuid
        signature = @client_key.sign(nil, sign_material("Pair-Setup-Controller-Sign", @identifier, client_public))

        sealed = AEAD.encrypt(
          key: @pair_setup_key, nonce: AEAD.nonce("PS-Msg05"),
          plaintext: TLV8.encode([
            TLV8::Item.new(IDENTIFIER, @identifier.b),
            TLV8::Item.new(PUBLIC, client_public),
            TLV8::Item.new(SIGNATURE, signature)
          ])
        )
        last = exchange(session, { STATE => "\x05".b, ENCRYPTED => sealed })

        identity = TLV8.decode(
          AEAD.decrypt(key: @pair_setup_key, nonce: AEAD.nonce("PS-Msg06"), ciphertext: tlv(last, ENCRYPTED))
        )
        accessory_public = tlv(identity, PUBLIC)
        accessory_signature = tlv(identity, SIGNATURE)
        material = sign_material("Pair-Setup-Accessory-Sign", tlv(identity, IDENTIFIER), accessory_public)

        unless Keys.ed25519_public(accessory_public).verify(nil, accessory_signature, material)
          raise Airplay::AuthFailedError.new("receiver identity signature does not verify", code: :auth_failed)
        end

        @record = (@store || CredentialStore.new).write(
          "device" => device_key(session),
          "identifier" => @identifier,
          "client_public" => Airplay::Plist::Data.new(client_public),
          "client_private" => Airplay::Plist::Data.new(Keys.raw_private(@client_key)),
          "accessory_public" => Airplay::Plist::Data.new(accessory_public),
          "accessory_signature" => Airplay::Plist::Data.new(accessory_signature),
          "permissions" => 1
        )
      end

      def sign_material(prefix, identifier, public_key)
        HKDF.expand(key, salt: "#{prefix}-Salt", info: "#{prefix}-Info") + identifier.b + public_key.b
      end

      # shortcut: the device model has no stable identifier yet, sanitize its name.
      def device_key(session)
        name = @device || (session.respond_to?(:device) ? session.device.name : "device")
        CredentialStore.key_for(name)
      end

      def exchange(session, values)
        body = TLV8.encode(values.map { |type, value| TLV8::Item.new(type, value) })
        response = session.request("POST", "/pair-setup", body: body,
                                                        headers: { HEADER => transient? ? "4" : "3" })
        Unsupported.check!(response.headers["x-airplay-auth"])

        items = TLV8.decode(response.body)
        error = tlv(items, ERROR)
        if error
          raise_pairing_error(error.getbyte(0))
        end

        items
      end

      def raise_pairing_error(value)
        code = ERRORS.fetch(value, :connect_failed)
        error_class = code == :auth_failed ? Airplay::AuthFailedError : Airplay::TransportError
        raise error_class.new("pair-setup rejected with error 0x#{format("%02x", value)}", code: code)
      end

      def tlv(items, type)
        items.find { |item| item.type == type }&.value
      end

      def padded(value)
        value.to_s(2).rjust(SRP::GROUP_BYTES, "\0")
      end
    end
  end
end
