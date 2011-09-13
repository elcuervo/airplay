require File.expand_path("helper", File.dirname(__FILE__))

scope do
  setup do
    @airplay = Airplay::Client.new
  end

  test "connect to an authenticated source" do
    VCR.use_cassette("authenticate all the things!") do
      @airplay.use("Apple TV")
      @airplay.password("password")

      assert @airplay.scrub.has_key?("duration")
      assert @airplay.scrub.has_key?("position")
    end
  end
end
