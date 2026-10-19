require "openssl"

require "airplay/errors"

module Airplay
  module Pairing
    # Public: ChaCha20-Poly1305 frame codec for one direction of a channel.
    class Frame
      MAX_LENGTH = 1024
      TAG_LENGTH = 16

      attr_reader :counter

      def initialize(key, counter: 0)
        @key = key.to_s.b
        @counter = counter
      end

      def encrypt(plaintext)
        data = plaintext.to_s.b
        raise Airplay::ProtocolError.new("frame too large", code: :frame_too_large) if data.bytesize > MAX_LENGTH

        length = [data.bytesize].pack("v")
        cipher = OpenSSL::Cipher.new("chacha20-poly1305")
        cipher.encrypt
        cipher.key = @key
        cipher.iv = nonce(@counter)
        cipher.auth_data = length
        ciphertext = cipher.update(data) + cipher.final
        tag = cipher.auth_tag
        @counter += 1

        length + ciphertext + tag
      rescue OpenSSL::Cipher::CipherError => error
        raise Airplay::ProtocolError.new("frame encryption failed: #{error.message}", code: :frame_encryption_failed)
      end

      def decrypt(frame)
        data = frame.to_s.b
        raise Airplay::ProtocolError.new("truncated frame", code: :truncated_frame) if data.bytesize < 2

        length = data.byteslice(0, 2).unpack1("v")
        raise Airplay::ProtocolError.new("oversized frame", code: :oversized_frame) if length > MAX_LENGTH
        raise Airplay::ProtocolError.new("truncated frame", code: :truncated_frame) if data.bytesize < 2 + length + TAG_LENGTH

        ciphertext = data.byteslice(2, length)
        tag = data.byteslice(2 + length, TAG_LENGTH)

        cipher = OpenSSL::Cipher.new("chacha20-poly1305")
        cipher.decrypt
        cipher.key = @key
        cipher.iv = nonce(@counter)
        cipher.auth_tag = tag
        cipher.auth_data = data.byteslice(0, 2)
        plaintext = cipher.update(ciphertext) + cipher.final
        @counter += 1

        plaintext
      rescue OpenSSL::Cipher::CipherError
        raise Airplay::AuthFailedError.new("frame authentication failed", code: :auth_failed)
      end

      private

      def nonce(value)
        "\0\0\0\0".b + [value].pack("Q<")
      end
    end
  end
end
