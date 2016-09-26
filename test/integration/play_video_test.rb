require "integration_helper"

scope "Sending video to a device" do
  setup do
    @device = test_device
  end

  test "plays a video url" do
    player = @device.play(sample_video)
    player.progress -> info {player.state }
    sleep 1 while !player.played?

    assert player.played?
  end
end
