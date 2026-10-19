require "openssl"

require "airplay/errors"

module Airplay
  module Pairing
    # Public: ChaCha20-Poly1305 one-shot sealing for the pair-setup identity exchange.
    module AEAD
      TAG_LENGTH = 16

      class << self
        def encrypt(key:, nonce:, plaintext:, aad: nil)
          cipher = OpenSSL::Cipher.new("chacha20-poly1305")
          cipher.encrypt
          cipher.key = key
          cipher.iv = nonce
          cipher.auth_data = aad.to_s
          cipher.update(plaintext) + cipher.final + cipher.auth_tag
        end

        def decrypt(key:, nonce:, ciphertext:, aad: nil)
          data = ciphertext.to_s.b
          if data.bytesize <= TAG_LENGTH
            raise Airplay::AuthFailedError.new("sealed data is too short", code: :auth_failed)
          end

          cipher = OpenSSL::Cipher.new("chacha20-poly1305")
          cipher.decrypt
          cipher.key = key
          cipher.iv = nonce
          cipher.auth_tag = data.byteslice(-TAG_LENGTH, TAG_LENGTH)
          cipher.auth_data = aad.to_s
          cipher.update(data.byteslice(0, data.bytesize - TAG_LENGTH)) + cipher.final
        rescue OpenSSL::Cipher::CipherError => error
          raise Airplay::AuthFailedError.new("sealed data failed authentication: #{error.message}",
                                             code: :auth_failed)
        end

        def nonce(label)
          label.to_s.b.ljust(12, "\0")
        end
      end
    end
  end
end
