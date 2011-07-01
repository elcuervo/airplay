require File.expand_path("helper", File.dirname(__FILE__))

scope do
  test "check video protocol class" do
    image_protocol = Airplay::Protocol::Video.new("127.0.0.1")
    assert_equal "/play", image_protocol.resource
  end
end

scope do
end
