require_relative "../test_helper"

describe "Airplay should list the slideshow features" do
  it "should list features" do
    with_cassette("listing slideshow features") do
      features = Airplay.slideshow.features
      assert_equal 13, features.size
    end
  end
end
