require "openssl"
require "securerandom"

require "airplay/errors"

module Airplay
  module Pairing
    # Public: SRP-6a client for the HAP Pair-Setup exchange.
    class SRP
      # RFC 5054 Appendix A, 3072-bit group.
      PRIME_3072 = <<~HEX.delete("\n")
        FFFFFFFFFFFFFFFFC90FDAA22168C234C4C6628B80DC1CD129024E088A67CC74020BBEA6
        3B139B22514A08798E3404DDEF9519B3CD3A431B302B0A6DF25F14374FE1356D6D51C245
        E485B576625E7EC6F44C42E9A637ED6B0BFF5CB6F406B7EDEE386BFB5A899FA5AE9F2411
        7C4B1FE649286651ECE45B3DC2007CB8A163BF0598DA48361C55D39A69163FA8FD24CF5F
        83655D23DCA3AD961C62F356208552BB9ED529077096966D670C354E4ABC9804F1746C08
        CA18217C32905E462E36CE3BE39E772C180E86039B2783A2EC07A28FB5C55DF06F4C52C9
        DE2BCBF6955817183995497CEA956AE515D2261898FA051015728E5A8AAAC42DAD33170D
        04507A33A85521ABDF1CBA64ECFB850458DBEF0A8AEA71575D060C7DB3970F85A6E1E4C7
        ABF5AE8CDB0933D71E8C94E04A25619DCEE3D2261AD2EE6BF12FFA06D98A0864D8760273
        3EC86A64521F2B18177B200CBBE117577A615D6C770988C0BAD946E208E24FA074E5AB31
        43DB5BFCE0FD108E4B82D120A93AD2CAFFFFFFFFFFFFFFFF
      HEX

      N = OpenSSL::BN.new(PRIME_3072, 16)
      G = OpenSSL::BN.new("5", 10)
      IDENTITY = "Pair-Setup"
      GROUP_BYTES = (N.num_bits + 7) / 8

      attr_reader :public, :key, :proof

      def initialize(pin:, private: nil)
        @pin = pin.to_s
        scalar = private || SecureRandom.random_number(2**1024)
        @a = bn(scalar)
        @public = G.mod_exp(@a, N)
        @server_proof = nil
      end

      # Public: Computes the shared key and client proof from the receiver's B and salt.
      def process(server_public, salt)
        b = bn(server_public)
        raise Airplay::ProtocolError.new("invalid SRP public value", code: :invalid_srp) if (b % N).zero?

        salt = salt.to_s.b
        k = int_hash(pad(N), pad(G))
        x = int_hash(salt, hash(IDENTITY, @pin, joiner: ":"))
        u = int_hash(pad(@public), pad(b))
        verifier = G.mod_exp(bn(x), N)
        base = (b - (bn(k) * verifier)) % N
        exponent = @a + bn(u * x)
        premaster = base.mod_exp(exponent, N)

        @key = hash(premaster)
        @proof = hash(
          int_bytes(int_hash(N.to_s(2)) ^ int_hash(int_bytes(5))),
          int_bytes(int_hash(IDENTITY)),
          salt,
          @public.to_s(2),
          b.to_s(2),
          @key
        )
        @server_proof = hash(@public.to_s(2), @proof, @key)
        self
      end

      def valid_server_proof?(value)
        secure_compare(@server_proof.to_s, value.to_s)
      end

      private

      def bn(value)
        return value if value.is_a?(OpenSSL::BN)

        if value.is_a?(Integer)
          OpenSSL::BN.new(value.to_s, 10)
        else
          OpenSSL::BN.new(value.to_s.unpack1("H*"), 16)
        end
      end

      def pad(value)
        bytes = value.is_a?(OpenSSL::BN) ? value.to_s(2) : int_bytes(value)
        bytes.rjust(GROUP_BYTES, "\0")
      end

      def int_bytes(value)
        hex = value.to_i.to_s(16)
        hex = "0#{hex}" if hex.length.odd?
        [hex].pack("H*")
      end

      def int_hash(*parts)
        hash(*parts).unpack1("H*").to_i(16)
      end

      def hash(*parts, joiner: "")
        digest = OpenSSL::Digest::SHA512.new
        parts.each_with_index do |part, index|
          digest.update(joiner) if index.positive?
          digest.update(part.is_a?(String) ? part.b : part.to_s(2))
        end
        digest.digest
      end

      def secure_compare(left, right)
        return false unless left.bytesize == right.bytesize

        result = 0
        left.bytes.zip(right.bytes) { |a, b| result |= a ^ b }
        result.zero?
      end
    end
  end
end
