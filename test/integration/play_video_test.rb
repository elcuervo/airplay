require "integration_helper"

scope "Sending video to a device" do
  setup do
    @device = test_device
    @url = "http://download.openbricks.org/sample/H264/big_buck_bunny_1080p_H264_AAC_25fps_7200K_short.MP4"
  end

  test "plays a video url" do
    player = @device.play(@url)
    player.progress -> info { player.state }
    timeout(10) do
      sleep 1 while !player.played?
    end

    assert player.played?
  end
end
