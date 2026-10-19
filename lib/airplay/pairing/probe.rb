require "openssl"

require "airplay/errors"

module Airplay
  module Pairing
    # Public: Verifies the crypto primitives this build needs.
    module Probe
      PRIMITIVES = {
        "ChaCha20-Poly1305" => -> { OpenSSL::Cipher.new("chacha20-poly1305") },
        "X25519" => -> { OpenSSL::PKey.generate_key("X25519") },
        "Ed25519" => -> { OpenSSL::PKey.generate_key("Ed25519") },
        "HKDF-SHA512" => -> { OpenSSL::KDF.hkdf("seed", salt: "salt", info: "info", length: 32, hash: "SHA512") },
        "SHA-512" => -> { OpenSSL::Digest.new("SHA512").digest("seed") }
      }.freeze

      class << self
        def check!(primitives = PRIMITIVES)
          primitives.each do |name, operation|
            operation.call
          rescue StandardError => error
            raise Airplay::UnsupportedError.new(
              "missing crypto primitive #{name}: #{error.class}",
              code: :unsupported_crypto
            )
          end
          true
        end
      end
    end
  end
end
