require "integration_helper"

scope "Sending images to a @device" do
  setup do
    @device = test_device
  end

  test "being a file path" do
    assert @device.view(sample_images[0])
  end

  test "being a raw image" do
    image = File.read(sample_images[1])
    assert @device.view(image)
  end

  test "being a raw binary image" do
    image = File.open(sample_images[1], "rb").read
    assert @device.view(image)
  end

  test "being a IO stream" do
    image = StringIO.new(File.read(sample_images[2]))
    assert @device.view(image)
  end

  test "being a URL" do
    image = "https://github.com/elcuervo/airplay/raw/master/doc/img/logo.png"
    assert @device.view(image)
  end

  test "sending an unsupported type" do
    assert_raise Airplay::Viewer::UnsupportedType do
      @device.view(42)
    end
  end
end
