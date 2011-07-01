require File.expand_path("helper", File.dirname(__FILE__))

scope do
  test "check image protocol" do
    image_protocol = Airplay::Protocol::Image.new("127.0.0.1")
    assert_equal "/photos", image_protocol.resource
  end
end

scope do
  test "send an image to the server" do
    airplay = Airplay::Client.new
    airplay.use("elCuervo")
    assert_equal true, airplay.send_image("./test/fixtures/image.gif")
  end
end
