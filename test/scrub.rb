require File.expand_path("helper", File.dirname(__FILE__))

scope do
  test "check image protocol class" do
    scrub_protocol = Airplay::Protocol::Scrub.new("127.0.0.1")
    assert_equal "/scrub", scrub_protocol.resource
  end
end

scope do
  setup do
    @airplay = Airplay::Client.new(false, MockedBrowser)
  end

  test "check scrub status" do
    VCR.use_cassette("get current scrub from apple tv") do
      assert @airplay.scrub.has_key?("duration")
      assert @airplay.scrub.has_key?("position")
    end
  end

  test "move to a given position" do
    VCR.use_cassette("go to a given position in the video") do
      @airplay.send_video("http://www.yo-yo.org/mp4/yu.mp4")
      duration = @airplay.scrub.fetch("duration")

      assert @airplay.scrub(duration/2)
      assert @airplay.scrub("50%")
    end
  end
end
