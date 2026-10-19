require "test_helper"
require "airplay/pairing/verify"

# RFC 7748 section 6.1 X25519 vectors.
class VerifyTest < Minitest::Test
  include Airplay::Pairing

  ALICE_PRIVATE = "77076d0a7318a57d3c16c17251b26645df4c2f87ebc0992ab177fba51db92c2a"
  ALICE_PUBLIC = "8520f0098930a754748b7ddcb43ef75a0dbf3a0d26381af4eba4a98eaa9b4e6a"
  BOB_PUBLIC = "de9edb7d7b7dc1b4d35b61c2ece435373f8343c85b78674dadfc7e146f882b4f"
  SHARED = "4a5d9d5ba4ce2de1728e3bf480350f25e07e21c947d19e3376f09b3c1e161742"

  class StubConnection
    Response = Struct.new(:body) do
      def headers
        {}
      end
    end

    attr_reader :requests

    def initialize(responses)
      @responses = responses
      @requests = []
    end

    def request(_method, _path, body:, headers: {})
      @requests << body
      Response.new(@responses.shift)
    end

    def encrypt!(*); end
  end

  def test_the_shared_secret_matches_the_rfc_vector
    accessory = OpenSSL::PKey.generate_key("Ed25519")
    stub = StubConnection.new([m2(accessory), TLV8.encode([TLV8::Item.new(6, "\x04".b)])])

    verify = Verify.new(record(accessory), private_key: hex(ALICE_PRIVATE)).run(stub)

    assert_equal SHARED, verify.shared_secret.unpack1("H*")
    assert_equal "accessory-id", verify.accessory_identifier
    assert_equal 2, stub.requests.length
  end

  def test_a_forged_receiver_signature_fails_authentication
    accessory = OpenSSL::PKey.generate_key("Ed25519")
    impostor = OpenSSL::PKey.generate_key("Ed25519")
    stub = StubConnection.new([m2(impostor), TLV8.encode([TLV8::Item.new(6, "\x04".b)])])

    error = assert_raises(Airplay::AuthFailedError) do
      Verify.new(record(accessory), private_key: hex(ALICE_PRIVATE)).run(stub)
    end

    assert_equal :auth_failed, error.code
  end

  private

  def m2(signer)
    encryption_key = HKDF.expand(hex(SHARED), salt: "Pair-Verify-Encrypt-Salt",
                                               info: "Pair-Verify-Encrypt-Info")
    material = hex(BOB_PUBLIC) + "accessory-id" + hex(ALICE_PUBLIC)
    identity = TLV8.encode([
      TLV8::Item.new(1, "accessory-id"),
      TLV8::Item.new(10, signer.sign(nil, material))
    ])

    TLV8.encode([
      TLV8::Item.new(6, "\x02".b),
      TLV8::Item.new(3, hex(BOB_PUBLIC)),
      TLV8::Item.new(5, AEAD.encrypt(key: encryption_key, nonce: AEAD.nonce("PV-Msg02"),
                                     plaintext: identity))
    ])
  end

  def record(accessory)
    {
      "identifier" => "controller-id",
      "client_public" => Airplay::Plist::Data.new(hex(ALICE_PUBLIC)),
      "client_private" => Airplay::Plist::Data.new(hex(ALICE_PRIVATE)),
      "accessory_public" => Airplay::Plist::Data.new(Keys.raw_public(accessory))
    }
  end

  def hex(value)
    [value].pack("H*")
  end
end
