require "test_helper"
require "airplay"

SERVER_URL = ENV.fetch("TEST_TV_URL", "localhost:7000")

Airplay.configure do |c|
  c.autodiscover = false
  c.log_level = 1
end

Airplay.devices.add("Block TV", SERVER_URL)

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

def sample_video
  @_video ||= "http://www.sample-videos.com/video/mp4/480/big_buck_bunny_480p_1mb.mp4"
end
