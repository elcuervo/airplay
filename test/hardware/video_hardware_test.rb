require "test_helper"
require "json"
require "tmpdir"

class VideoHardwareTest < Airplay::TestCase
  # Public: Per-run record for the opt-in video lane.
  Report = Struct.new(:scenario, :route, :device_model, :firmware, :timing_mode, :profile,
                      :states, :event_count, :playback_info_status, :now_playing,
                      :comparison, :outcome, keyword_init: true) do
    def render
      "scenario=#{scenario} route=#{route} device=#{device_model} firmware=#{firmware} " \
        "timing=#{timing_mode} profile=#{profile} states=#{Array(states).join('>')} " \
        "events=#{event_count} playback_info=#{playback_info_status} " \
        "now_playing=#{now_playing} comparison=#{comparison} outcome=#{outcome}"
    end

    def to_h
      members.to_h { |member| [member, public_send(member)] }
    end
  end

  def test_the_remote_hls_scenario_is_recorded
    run_scenario(:remote_hls, ENV["AIRPLAY_HARDWARE_HLS_URL"])
  end

  def test_the_local_hls_scenario_is_recorded
    run_scenario(:local_hls, ENV["AIRPLAY_HARDWARE_LOCAL_HLS"])
  end

  def test_the_local_progressive_scenario_is_recorded
    run_scenario(:local_progressive, ENV["AIRPLAY_HARDWARE_LOCAL_FILE"])
  end

  def test_the_report_names_every_required_field
    report = Report.new(scenario: :remote_hls, route: :queue, device_model: "AppleTV6,2",
                        firmware: "870.14.1", timing_mode: "NTP", profile: "tvos-26.5",
                        states: %i[loading playing stopped], event_count: 3,
                        playback_info_status: 404, now_playing: "rendered",
                        comparison: "modern=played legacy=failed delivered=modern",
                        outcome: :played)
    line = report.render

    %w[scenario= route= device= firmware= timing= profile= states= events=
       playback_info= now_playing= comparison= outcome=].each do |field|
      assert_includes line, field
    end
    assert_includes line, "870.14.1"
    assert_includes line, "NTP"
    assert_includes line, "tvos-26.5"
    assert_includes line, "delivered=modern"
  end

  def test_a_playback_info_capture_records_its_device_and_firmware
    Dir.mktmpdir do |dir|
      report = Report.new(scenario: :remote_hls, device_model: "AppleTV6,2",
                          firmware: "870.14.1")
      path = commit_capture(dir, report, "rate" => 1.0, "duration" => 30.0)

      fixture = JSON.parse(File.read(path))
      assert_equal "remote_hls", fixture["provenance"]["scenario"]
      assert_equal "AppleTV6,2", fixture["provenance"]["device_model"]
      assert_equal "870.14.1", fixture["provenance"]["firmware"]
      assert_equal 30.0, fixture["payload"]["duration"]
    end
  end

  private

  def host
    ENV["AIRPLAY_HARDWARE_HOST"]
  end

  def run_scenario(name, media)
    skip "set AIRPLAY_HARDWARE_HOST to run the video hardware lane" unless host
    skip "set the media location for the #{name} scenario" if media.to_s.empty?

    device = Airplay::Device.new(
      name: ENV.fetch("AIRPLAY_HARDWARE_NAME", "hardware"),
      host: host,
      port: ENV.fetch("AIRPLAY_HARDWARE_PORT", 7000)
    )
    capabilities = hardware_capabilities(device)
    decision = Airplay::Player.decide(capabilities)
    record = Report.new(scenario: name, route: decision.route, device_model: device.name,
                        firmware: capabilities&.srcvers&.to_s, profile: decision.profile&.id,
                        states: [], event_count: 0)

    begin
      modern = play_once(device, capabilities, media, force_legacy: false, record: record)
      legacy = play_once(device, capabilities, media, force_legacy: true, record: nil)
      record.comparison = "modern=#{modern} legacy=#{legacy} " \
                          "delivered=#{modern == :played ? 'modern' : legacy == :played ? 'legacy' : 'none'}"
      record.now_playing = "pushed without an origin registration; rendering not observable"
      record.outcome = modern
    rescue Airplay::Error => error
      record.outcome = "#{error.code}:#{error.message}"
    ensure
      puts record.render
      assert record.outcome, "the run recorded an outcome"
    end
  end

  # Public: One route run; fills the record it is given.
  def play_once(device, capabilities, media, force_legacy:, record:)
    Airplay.sync do
      Airplay::Player.open(device, capabilities: capabilities,
                                   force_legacy: force_legacy, window: 15) do |player|
        player.state.on_change { |state| record.states << state.status } if record
        player.play(media)
        player.wait
        if record && player.respond_to?(:session)
          record.timing_mode = player.session.timing_protocol
          record.event_count = player.session.events.length
          status, payload = player.session.playback_info
          record.playback_info_status = status
          commit_capture(File.expand_path("../fixtures/queue", __dir__), record, payload) if
            status == 200 && payload && !payload.empty?
        end
      end
    end
    :played
  rescue Airplay::Error => error
    raise if record

    error.code
  end

  def hardware_capabilities(device)
    info = Airplay.sync do
      Airplay::Session.open(device) { |session| session.server_info }
    end
    Airplay::Discovery::Capabilities.new(info)
  rescue Airplay::Error
    nil
  end

  def commit_capture(directory, report, payload)
    path = File.join(directory, "playback-info-#{report.firmware || 'unknown'}.json")
    provenance = JSON.parse(JSON.generate(report.to_h))
    File.write(path, JSON.pretty_generate("provenance" => provenance, "payload" => payload))
    path
  end
end
