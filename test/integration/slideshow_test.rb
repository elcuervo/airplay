require_relative "../test_helper"

describe "Airplay should list the slideshow features" do
  it "should a list of features" do
    with_cassette("listing slideshow features") do
      features = Airplay.slideshow.features
      assert features.size > 10
    end
  end

  it "should start a slideshow of images" do
    skip("There are some missing parts in the reverse streaming")

    with_cassette("playing a given slideshow") do
      Airplay.use "corax"
      Airplay.slideshow << [
        "test/fixtures/files/image_01.jpg",
        "test/fixtures/files/image_02.jpg"
      ]

      Airplay.slideshow.play
      sleep 10
      Airplay.slideshow.stop
    end
  end
end
