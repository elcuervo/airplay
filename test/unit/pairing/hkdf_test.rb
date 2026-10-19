require "test_helper"
require "airplay/pairing/hkdf"
require "json"

class HKDFTest < Minitest::Test
  VECTOR = JSON.parse(File.read("test/fixtures/pairing/hkdf_vectors.json"))
  SECRET = [VECTOR["secret"]].pack("H*")

  def test_control_and_event_vectors
    write, read = Airplay::Pairing::HKDF.control_keys(SECRET)
    event_write, event_read = Airplay::Pairing::HKDF.event_keys(SECRET)

    assert_equal VECTOR["derived"]["control_write"], write.unpack1("H*")
    assert_equal VECTOR["derived"]["control_read"], read.unpack1("H*")
    assert_equal VECTOR["derived"]["events_write"], event_write.unpack1("H*")
    assert_equal VECTOR["derived"]["events_read"], event_read.unpack1("H*")

    keys = [write, read, event_write, event_read]
    assert_equal 4, keys.uniq.length
  end
end
