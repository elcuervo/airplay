require "openssl"

require "airplay/errors"

module Airplay
  module Pairing
    # Public: Converts between the raw 32-byte X25519/Ed25519 keys on the wire
    # and the DER-shaped keys OpenSSL's Ruby binding accepts.
    module Keys
      RAW_LENGTH = 32
      X25519_PUBLIC = ["302a300506032b656e032100"].pack("H*")
      X25519_PRIVATE = ["302e020100300506032b656e04220420"].pack("H*")
      ED25519_PUBLIC = ["302a300506032b6570032100"].pack("H*")
      ED25519_PRIVATE = ["302e020100300506032b657004220420"].pack("H*")

      class << self
        def x25519_public(raw) = import(X25519_PUBLIC, raw)
        def x25519_private(raw) = import(X25519_PRIVATE, raw)
        def ed25519_public(raw) = import(ED25519_PUBLIC, raw)
        def ed25519_private(raw) = import(ED25519_PRIVATE, raw)

        def raw_public(key) = extract(key.public_to_der, [X25519_PUBLIC, ED25519_PUBLIC])
        def raw_private(key) = extract(key.private_to_der, [X25519_PRIVATE, ED25519_PRIVATE])

        private

        def import(prefix, raw)
          bytes = raw.to_s.b
          unless bytes.bytesize == RAW_LENGTH
            raise Airplay::ProtocolError.new("key must be #{RAW_LENGTH} raw bytes", code: :invalid_key)
          end

          OpenSSL::PKey.read(prefix + bytes)
        end

        def extract(der, prefixes)
          prefix = prefixes.find { |candidate| der.start_with?(candidate) }
          raise Airplay::ProtocolError.new("unexpected key encoding", code: :invalid_key) unless prefix

          der.byteslice(prefix.bytesize, RAW_LENGTH)
        end
      end
    end
  end
end
