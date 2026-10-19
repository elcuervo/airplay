require "test_helper"
require "airplay/pairing/srp"
require "json"

class SRPTest < Minitest::Test
  VECTOR = JSON.parse(File.read("test/fixtures/pairing/srp_vector.json"))

  def test_golden_vector
    srp = Airplay::Pairing::SRP.new(
      pin: VECTOR["pin"],
      private: VECTOR["a"].to_i(16)
    )

    srp.process([VECTOR["B"]].pack("H*"), [VECTOR["salt"]].pack("H*"))

    assert_equal VECTOR["A"].downcase, srp.public.to_s(16).downcase
    assert_equal VECTOR["key"], srp.key.unpack1("H*")
    assert_equal VECTOR["M1"], srp.proof.unpack1("H*")
    assert srp.valid_server_proof?([VECTOR["M2"]].pack("H*"))
  end

  def test_wrong_server_proof_is_rejected
    srp = Airplay::Pairing::SRP.new(pin: VECTOR["pin"], private: VECTOR["a"].to_i(16))
    srp.process([VECTOR["B"]].pack("H*"), [VECTOR["salt"]].pack("H*"))

    refute srp.valid_server_proof?("\0" * 64)
  end
end
