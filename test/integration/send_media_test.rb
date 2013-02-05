require_relative "../test_helper"

describe "Airplay sending media" do
  it "should send an image" do
    with_cassette("sending an image") do
      assert Airplay.view("test/fixtures/files/logo.png")
      assert Airplay.view(File.read("test/fixtures/files/logo.png"))
      assert Airplay.view(File.open("test/fixtures/files/logo.png"))
      assert Airplay.view("http://comicsymascomics.com/wp-content/uploads/images/31/v-de-vendetta.jpg")
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
      sleep 0.1
      Airplay.stop
    end
  end
end
