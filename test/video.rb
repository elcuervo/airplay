require File.expand_path("helper", File.dirname(__FILE__))

scope do
  test "check video protocol class" do
    image_protocol = Airplay::Protocol::Video.new("127.0.0.1")
    assert_equal "/video", image_protocol.resource
  end
end

scope do
  setup do
    @airplay = Airplay::Client.new
  end

  test "send a video to the server" do
    @airplay.use("elCuervo")
    assert_equal true, @airplay.send_video("http://www.yo-yo.org/mp4/yu.mp4")
  end

end
