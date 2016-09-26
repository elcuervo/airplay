require "integration_helper"

scope "Sending video to a device" do
  setup do
    @device = test_device
    @url = "http://www.sample-videos.com/video/mp4/480/big_buck_bunny_480p_1mb.mp4"
  end

  test "plays a video url" do
    player = @device.play(@url)
    player.progress -> info {player.state }
    sleep 1 while !player.played?

    assert player.played?
  end
end
