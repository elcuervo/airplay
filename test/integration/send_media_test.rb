require_relative "../test_helper"

describe "Airplay sending media" do
  it "should send an image" do
    with_cassette("sending an image") do
      Airplay.view("test/fixtures/files/logo.png")
    end
  end
end
