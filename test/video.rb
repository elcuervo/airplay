require File.expand_path("helper", File.dirname(__FILE__))

scope do
  test "check video protocol class" do
    image_protocol = Airplay::Protocol::Video.new("127.0.0.1")
    assert_equal "/play", image_protocol.resource
  end
end

scope do
  setup do
    @airplay = Airplay::Client.new(false, MockedBrowser)
  end

  test "send a video to the server" do
    VCR.use_cassette("send video to apple tv") do
      assert @airplay.send_video("http://www.yo-yo.org/mp4/yu.mp4").kind_of?(String)
    end
  end
end
