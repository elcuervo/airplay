require_relative "../test_helper"

describe "Airplay sending media" do
  it "should send an image" do
    with_cassette("sending an image") do
      Airplay.view("test/fixtures/files/logo.png")
    end
  end

  it "should play an entire video" do
    skip("Works, but I need a way to make Net::PTTH to work with VCR :/")

    with_cassette("play an entire video") do
      Airplay.play("test/fixtures/files/video.mp4")
      Airplay.player.wait
      assert Airplay.player.played?
    end
  end

  it "should stop any transmission" do
    with_cassette("stop any transmission") do
      Airplay.view("test/fixtures/files/logo.png")
      Airplay.stop
    end
  end
end
