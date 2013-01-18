require_relative "../test_helper"

describe "Airplay sending media" do
  it "should send an image" do
    with_cassette("sending an image") do
      Airplay.view("test/fixtures/files/logo.png")
    end
  end

  it "should stop any transmission" do
    with_cassette("stop any transmission") do
      Airplay.view("test/fixtures/files/logo.png")
      Airplay.stop
    end
  end
end
