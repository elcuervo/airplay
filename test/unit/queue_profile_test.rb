require "test_helper"

class QueueProfileTest < Airplay::TestCase
  def test_a_known_firmware_selects_its_profile
    profile = Airplay::Queue::Profile.select("870.14.1")

    assert_equal "tvos-26.5", profile.id
    assert_equal "AirPlay/870.14.1", profile.sender
    assert_equal "x-apple-stream-id", profile.stream_header
    assert_equal :receiver, profile.channel_identity
    assert_includes @output.string, "queue.profile"
    assert_includes @output.string, "tvos-26.5"
  end

  def test_a_firmware_prefix_matches
    assert_equal "tvos-18.4", Airplay::Queue::Profile.select("550.10.1").id
  end

  def test_an_unknown_firmware_uses_the_default_and_logs_the_reason
    profile = Airplay::Queue::Profile.select("999.9")

    assert_equal Airplay::Queue::Profile::DEFAULT, profile
    assert_includes @output.string, "unknown firmware"
    assert_includes @output.string, "default"
  end

  def test_no_reported_firmware_uses_the_default_and_logs_the_reason
    assert_equal Airplay::Queue::Profile::DEFAULT, Airplay::Queue::Profile.select(nil)
    assert_includes @output.string, "none reported"
  end

  def test_the_profile_table_pins_every_firmware_it_names
    Airplay::Queue::Profile::TABLE.each do |profile|
      profile.firmwares.each do |firmware|
        assert_equal profile.id, Airplay::Queue::Profile.select(firmware).id
      end
    end
  end
end
