require File.expand_path("helper", File.dirname(__FILE__))

scope do
  test "check image protocol class" do
    scrub_protocol = Airplay::Protocol::Scrub.new("127.0.0.1")
    assert_equal "/scrub", scrub_protocol.resource
  end
end

scope do
  setup do
    @airplay = Airplay::Client.new
  end

  test "check scrub status" do
    VCR.use_cassette("get current scrub from apple tv") do
      @airplay.use("Apple TV")
      assert @airplay.scrub.has_key?("duration")
      assert @airplay.scrub.has_key?("position")
    end
  end
end
