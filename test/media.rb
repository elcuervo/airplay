require File.expand_path("helper", File.dirname(__FILE__))

scope do
  test "check media protocol class" do
    image_protocol = Airplay::Protocol::Media.new("127.0.0.1")
    assert_equal "/play", image_protocol.resource
    assert_equal "/stop", image_protocol.stop_resource
    assert_equal "/rate", image_protocol.pause_resource
  end
end

scope do
  setup do
    @airplay = Airplay::Client.new(false, MockedBrowser)
  end

  test "send a video to the server" do
    VCR.use_cassette("send video to apple tv") do
      assert @airplay.send_video("http://www.yo-yo.org/mp4/yu.mp4")
    end
  end

  test "player capabilities" do
    VCR.use_cassette("control a video being played in apple tv") do
      player = @airplay.send_video("http://www.yo-yo.org/mp4/yu.mp4")

      assert player.pause
      assert player.resume
      assert player.scrub.has_key?("position")
      assert player.scrub.has_key?("duration")
      assert player.scrub("10%")
      assert player.stop
    end
  end

  test "send audio to the server" do
    VCR.use_cassette("send audio to apple tv") do
      assert @airplay.send_audio("http://www.robtowns.com/music/blind_willie.mp3")
    end
  end

  test "raise an exception on invalid media url" do
    assert_raise Airplay::Protocol::InvalidMediaError do
      @airplay.send_video("Surculus Fructum!")
    end
  end
end
