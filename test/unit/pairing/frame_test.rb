require "test_helper"
require "airplay/pairing/frame"
require "json"

class FrameTest < Minitest::Test
  VECTOR = JSON.parse(File.read("test/fixtures/pairing/frame_vector.json"))
  KEY = [VECTOR["key"]].pack("H*")
  PLAINTEXT = [VECTOR["plaintext"]].pack("H*")
  GOLDEN_FRAME = VECTOR["frame"]

  def test_golden_frame
    frame = Airplay::Pairing::Frame.new(KEY)

    assert_equal GOLDEN_FRAME, frame.encrypt(PLAINTEXT).unpack1("H*")
    assert_equal 1, frame.counter
  end

  def test_round_trip_and_counters
    sender = Airplay::Pairing::Frame.new(KEY)
    receiver = Airplay::Pairing::Frame.new(KEY)

    3.times do |index|
      frame = sender.encrypt("frame #{index}")
      assert_equal "frame #{index}", receiver.decrypt(frame)
    end

    assert_equal 3, sender.counter
    assert_equal 3, receiver.counter
  end

  def test_corrupted_tag_fails_closed
    sender = Airplay::Pairing::Frame.new(KEY)
    receiver = Airplay::Pairing::Frame.new(KEY)
    frame = sender.encrypt(PLAINTEXT)
    frame.setbyte(frame.bytesize - 1, frame.getbyte(frame.bytesize - 1) ^ 0xFF)

    error = assert_raises(Airplay::AuthFailedError) { receiver.decrypt(frame) }
    assert_equal :auth_failed, error.code
  end

  def test_oversized_and_truncated_frames_are_rejected
    receiver = Airplay::Pairing::Frame.new(KEY)

    oversized = [2000].pack("v") + ("x" * 2000)
    error = assert_raises(Airplay::ProtocolError) { receiver.decrypt(oversized) }
    assert_equal :oversized_frame, error.code

    truncated = [10].pack("v") + "short"
    error = assert_raises(Airplay::ProtocolError) { receiver.decrypt(truncated) }
    assert_equal :truncated_frame, error.code
  end
end
