require_relative "../test_helper"

describe "Airplay should list the slideshow features" do
  it "should a list of features" do
    with_cassette("listing slideshow features") do
      features = Airplay.slideshow.features
      assert_equal 11, features.size
    end
  end

  it "should start a slideshow of images" do
    with_cassette("playing a given slideshow") do
      Airplay.slideshow << [
        "test/fixtures/files/image_01.jpg",
        "test/fixtures/files/image_02.jpg"
      ]

      Airplay.slideshow.play
      sleep 20
      Airplay.slideshow.stop
    end
  end
end
