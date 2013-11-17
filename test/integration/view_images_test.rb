require "integration_helper"

describe "Sending images to a device" do
  Given(:device) { test_device }

  context "being a file path" do
    When(:view) { device.view(sample_images[0]) }
    Then { view == true }
  end

  context "being a raw image" do
    Given(:image) { File.read(sample_images[1]) }
    When(:view)   { device.view(image) }
    Then { view == true }
  end

  context "being a IO stream" do
    Given(:image) { StringIO.new(File.read(sample_images[2])) }
    When(:view)   { device.view(image) }
    Then { view == true }
  end

  context "being a URL" do
    Given(:image) { "https://github.com/elcuervo/airplay/raw/master/doc/img/logo.png" }
    When(:view)   { device.view(image) }
    Then { view == true }
  end

  context "sending an unsupported type" do
    When(:view) { device.view(42) }
    Then { view == Failure(TypeError) }
  end
end
