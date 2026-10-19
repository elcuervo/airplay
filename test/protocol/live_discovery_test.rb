require "test_helper"

class LiveDiscoveryTest < Airplay::TestCase
  def test_live_browse_on_the_host_interface
    skip "set AIRPLAY_LIVE_DISCOVERY=1 to browse the live network" unless ENV["AIRPLAY_LIVE_DISCOVERY"] == "1"

    result = Airplay::Discovery::Browser.new(
      families: [:ipv4]
    ).browse(window: Airplay.configuration.discovery_window, force: true)

    assert_includes %i[data_available window_elapsed], result.reason
  end
end
