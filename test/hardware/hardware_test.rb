require "test_helper"

class HardwareTest < Airplay::TestCase
  def test_a_configured_receiver_answers
    host = ENV["AIRPLAY_HARDWARE_HOST"]
    skip "set AIRPLAY_HARDWARE_HOST to run the hardware lane" unless host

    device = Airplay::Device.new(
      name: ENV.fetch("AIRPLAY_HARDWARE_NAME", "hardware"),
      host: host,
      port: ENV.fetch("AIRPLAY_HARDWARE_PORT", 7000)
    )

    response = Airplay.sync do
      Airplay::Session.open(device) { |session| session.get("/server-info") }
    end

    puts "hardware: host=#{host} status=#{response.status}"
    assert_includes 200..299, response.status
  end
end
