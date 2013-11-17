require "test_helper"
require "airplay"
require "celluloid/autostart"

def test_device
  @_device ||= Airplay["Block TV"]
end

def sample_images
  @_images ||= Dir.glob("test/fixtures/files/*.png")
end
