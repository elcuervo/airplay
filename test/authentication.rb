require File.expand_path("helper", File.dirname(__FILE__))

scope do
  test "connect to an authenticated source" do
    VCR.use_cassette("authenticate all the things!") do
      airplay = Airplay::Client.new(false, MockedBrowser)
      airplay.password("password")

      assert airplay.scrub.has_key?("duration")
      assert airplay.scrub.has_key?("position")
    end
  end
end
