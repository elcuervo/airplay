require "test_helper"
require "airplay"
require "celluloid/autostart"

Airplay.configure { |c| c.autodiscover = false }
Airplay.devices.add("Block TV", "blocktv.airplay.io:7000")

def test_device
  @_device ||= begin
    device = Airplay["Block TV"]
    device.password = ENV["TEST_TV_PASSWORD"]
    device
  end
end

def sample_images
  @_images ||= Dir.glob("test/fixtures/files/*.png")
end
