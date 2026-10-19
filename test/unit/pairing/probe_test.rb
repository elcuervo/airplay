require "test_helper"
require "airplay/pairing/probe"

class ProbeTest < Minitest::Test
  def test_checks_the_installed_primitives
    assert Airplay::Pairing::Probe.check!
  end

  def test_names_the_missing_primitive
    primitives = { "Ed25519" => -> { raise "missing" } }

    error = assert_raises(Airplay::UnsupportedError) do
      Airplay::Pairing::Probe.check!(primitives)
    end

    assert_match(/Ed25519/, error.message)
    assert_equal :unsupported_crypto, error.code
  end
end
