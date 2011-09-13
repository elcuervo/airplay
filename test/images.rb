require File.expand_path("helper", File.dirname(__FILE__))

scope do
  test "check image protocol class" do
    image_protocol = Airplay::Protocol::Image.new("127.0.0.1")
    assert_equal "/photo", image_protocol.resource
  end
end

scope do
  setup do
    @airplay = Airplay::Client.new(false, MockedBrowser)
  end

  test "send an image to the server" do
    VCR.use_cassette("send image to apple tv") do
      file_path = "./test/fixtures/image2.gif"
      assert @airplay.send_image(file_path).kind_of?(String)
      assert @airplay.send_image(File.open(file_path)).kind_of?(String)
    end
  end

  test "send an image to the server doing a dissolve" do
    VCR.use_cassette("send image to apple tv") do
      assert @airplay.send_image("./test/fixtures/image.gif", :dissolve).kind_of?(String)
    end
  end
end
