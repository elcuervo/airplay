require "test_helper"
require "airplay/control/session"
require "airplay/pairing/connection"

class PlayerInterfaceTest < Airplay::TestCase
  Response = Airplay::Pairing::Connection::Response

  class FakeQueueSession
    attr_reader :calls, :stream_id, :capabilities

    def initialize
      @calls = []
      @stream_id = 9
      @capabilities = Airplay::Discovery::Capabilities.new("srcvers" => "870.14.1")
    end

    def register_control_stream(profile:)
      @calls << [:control_stream, profile.id]
      stream_id
    end

    def on_event(&block)
      @listener = block
      self
    end

    def command(payload, stream_id:, profile:)
      @calls << [:command, payload["type"], payload["params"], stream_id, profile.id]
      Response.new(status: 200, headers: {}, body: "")
    end

    def playback_info
      [404, nil]
    end

    def close
      @calls << [:close]
    end

    def push(payload)
      @listener&.call(payload)
    end
  end

  class FakeLegacySession
    attr_reader :calls

    def initialize
      @calls = []
    end

    def play(url, position: 0.0)
      @calls << [:play, url, position]
    end

    def rate(value) = @calls << [:rate, value]
    def stop = @calls << [:stop]
    def scrub(position) = @calls << [:scrub, position]
    def playback_info = [200, { "rate" => 1.0, "duration" => 10.0, "position" => 1.0 }]
    def close = @calls << [:close]
  end

  def test_every_verb_on_the_queue_route_uses_queue_commands
    session = FakeQueueSession.new
    player = Airplay::Player::Queue.new(session: session,
                                        profile: Airplay::Queue::Profile::TVOS_26_5,
                                        media_host: nil, window: 0.1)
    player.play("http://example.com/a.mp4", position: 3.0)
    player.pause
    player.resume
    player.rate(2.0)
    player.seek(12.0)
    player.next
    player.previous
    player.stop

    types = session.calls.select { |call| call.first == :command }.map { |call| call[1] }
    assert_equal "insertPlayQueueItem", types.first
    assert_includes types, "setRate"
    assert_includes types, "seekToTime"
    assert_includes types, "selectQueueItem"
    assert_includes types, "removePlayQueueItem"

    rates = session.calls.select { |call| call.first == :command && call[1] == "setRate" }
                         .map { |call| call[2]["rate"] }
    assert_includes rates, 0.0
    assert_includes rates, 1.0
    assert_includes rates, 2.0
    seek = session.calls.find { |call| call.first == :command && call[1] == "seekToTime" }
    assert_equal 12.0, seek[2]["position"]
    refute(session.calls.any? { |call| %i[play scrub].include?(call.first) })
  end

  def test_every_verb_on_the_legacy_route_uses_legacy_endpoints
    session = FakeLegacySession.new
    player = Airplay::Player::Legacy.new(session: session)
    player.play("http://example.com/a.mp4")
    player.pause
    player.resume
    player.rate(2.0)
    player.seek(12.0)
    player.next
    player.previous
    player.stop

    assert_equal [:play, "http://example.com/a.mp4", 0.0], session.calls.first
    assert_includes session.calls, [:rate, 0]
    assert_includes session.calls, [:rate, 1]
    assert_includes session.calls, [:rate, 2.0]
    assert_includes session.calls, [:scrub, 12.0]
    assert_includes session.calls, [:stop]
    assert_equal 3, session.calls.count { |call| call.first == :play }
    refute(session.calls.any? { |call| call.first == :command })
  end

  def test_the_route_decision_reads_the_capability_model
    modern = Airplay::Discovery::Capabilities.new("features" => format("0x%x", 1 << 49),
                                                  "srcvers" => "870.14.1")
    legacy = Airplay::Discovery::Capabilities.new("features" => "0x1", "srcvers" => "220.68")
    unknown = Airplay::Discovery::Capabilities.new("features" => format("0x%x", 1 << 49))

    assert_equal :queue, Airplay::Player.decide(modern).route
    assert_equal :legacy, Airplay::Player.decide(legacy).route
    assert_equal :legacy, Airplay::Player.decide(unknown).route
    assert_includes Airplay::Player.decide(unknown).reason, "conservative policy"
    assert_equal :legacy, Airplay::Player.decide(modern, force_legacy: true).route
    assert_equal :legacy, Airplay::Player.decide(nil).route
  end

  def test_the_conservative_policy_can_be_turned_off
    Airplay.configure { |config| config.conservative_route = false }
    unknown = Airplay::Discovery::Capabilities.new("features" => format("0x%x", 1 << 49))

    decision = Airplay::Player.decide(unknown)
    assert_equal :queue, decision.route
    assert_equal "default", decision.profile.id
  end

  def test_the_shared_interface_names_every_transport_verb
    %i[play pause resume stop seek rate next previous wait].each do |verb|
      assert_respond_to Airplay::Player::Queue.allocate, verb
      assert_respond_to Airplay::Player::Legacy.allocate, verb
    end
  end
end
