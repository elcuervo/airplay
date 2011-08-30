require File.expand_path("helper", File.dirname(__FILE__))

scope do
  test "check image protocol class" do
    image_protocol = Airplay::Protocol::Image.new("127.0.0.1")
    assert_equal "/photo", image_protocol.resource
  end
end

scope do
  setup do
    @airplay = Airplay::Client.new
  end

  test "send an image to the server" do
    @airplay.use("Apple TV")
    assert @airplay.send_image("./test/fixtures/image2.gif").kind_of?(String)
  end

  test "send an image to the server doing a dissolve" do
    @airplay.use("Apple TV")
    assert @airplay.send_image("./test/fixtures/image.gif", :dissolve).kind_of?(String)
  end
end
