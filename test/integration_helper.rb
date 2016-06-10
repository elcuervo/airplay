require "test_helper"
require "airplay"

SERVER_URL = ENV.fetch("TEST_TV_URL", "some-apple-tv:7000")
Airplay.configure { |c| c.autodiscover = false }
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
  @_video ||= "http://movietrailers.apple.com/movies/universal/rush/rush-tlr3_480p.mov"
end
