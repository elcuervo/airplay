require "test_helper"
require "tmpdir"

class ControlSessionTest < Airplay::TestCase
  INFO = {
    "name" => "Fake",
    "deviceid" => "AA:BB",
    "features" => "0x40000000000"
  }.freeze

  def test_a_binary_info_response_is_decoded_and_feeds_the_capabilities
    with_control_session do |receiver, session|
      assert_equal "Fake", session.info["name"]
      assert_equal :authoritative, session.capabilities.source(:mask)
      assert_equal Integer("0x40000000000", 16), session.capabilities.mask

      session.load_info
      assert_equal 1, receiver.exchanges.count { |exchange| exchange.path == "/info" }
    end
  end

  def test_a_non_plist_info_body_fails_with_connect_failed
    error = assert_raises(Airplay::TransportError) do
      with_control_session(info: "not a plist") { |_receiver, _session| }
    end

    assert_equal :connect_failed, error.code
  end

  def test_setup_carries_identity_identifiers_and_timing
    with_control_session do |receiver, session|
      exchange = receiver.exchanges.find { |candidate| candidate.path == "/setup" }

      assert_equal "POST", exchange.method
      assert_equal session.session_id, exchange.plist["sessionUUID"]
      assert_equal session.group_id, exchange.plist["groupUUID"]
      refute_nil exchange.plist["deviceID"]
      assert_equal "NTP", exchange.plist["timingProtocol"]
      assert_operator exchange.plist["timingPort"], :>, 0
    end
  end

  def test_two_sessions_get_four_distinct_identifiers
    Dir.mktmpdir do |dir|
      store = Airplay::Pairing::CredentialStore.new(directory: dir)

      with_receiver(pairing: { pin: "1234", info_body: Airplay::Plist.dump(INFO) }) do |receiver|
        Airplay.sync do
          first = establish_pairing(store, receiver)
          one = Airplay::Control::Session.new(first, timing_port: 7001).establish
          first.close

          second = establish_pairing(store, receiver)
          two = Airplay::Control::Session.new(second, timing_port: 7001).establish
          second.close

          identifiers = [one.session_id, one.group_id, two.session_id, two.group_id]
          assert_equal 4, identifiers.uniq.length
        end
      end
    end
  end

  def test_a_confirmed_timing_protocol_is_recorded
    with_control_session(setup_body: { "timingProtocol" => "NTP", "timingPort" => 7010 }) do |_receiver, session|
      assert_equal "NTP", session.timing_protocol
      assert_equal 7010, session.timing_port
    end
  end

  def test_only_an_unimplemented_timing_protocol_fails_the_session
    error = assert_raises(Airplay::TimingError) do
      with_control_session(setup_body: { "timingProtocol" => "PTP", "timingPort" => 7011 }) do |_receiver, _session|
      end
    end

    assert_equal :timing_error, error.code
  end

  def test_info_and_setup_notes_match_the_wire_fields
    notes = File.read(File.expand_path("../../doc/pairing.md", __dir__))

    with_control_session do |receiver, _session|
      setup = receiver.exchanges.find { |exchange| exchange.path == "/setup" }
      setup.plist.each_key { |key| assert_includes notes, "`#{key}`" }

      Airplay::Discovery::Capabilities::KEY_FOR_FIELD.each_value do |key|
        assert_includes notes, "`#{key}`"
      end
      assert_includes notes, "`timingPort`"
      assert_includes notes, "`connect_failed`"
      assert_includes notes, "`timing_error`"
    end
  end

  def test_a_scripted_event_is_surfaced_on_the_reverse_channel
    with_control_session(events: [{ "type" => "playing" }]) do |_receiver, session|
      wait_until { !session.events.empty? }

      assert_equal "playing", session.events.first["type"]
    end
  end

  def test_losing_the_event_channel_is_recorded
    with_control_session(events: [{ "type" => "playing" }]) do |_receiver, session|
      wait_until { session.event_channel_lost? }

      assert session.event_channel_lost?
      assert_equal 1, session.events.length
    end
  end

  def test_feedback_is_sent_once_per_elapsed_interval
    clock = Airplay::FakeDevice::FakeClock.new
    Airplay.clock = clock

    with_control_session(clock: clock, feedback_interval: 2) do |receiver, session|
      refute session.tick
      clock.advance(2)
      assert session.tick
      refute session.tick
      assert_equal 1, receiver.exchanges.count { |exchange| exchange.path == "/feedback" }

      session.close
      clock.advance(2)
      refute session.tick
      assert_equal 1, receiver.exchanges.count { |exchange| exchange.path == "/feedback" }
    end
  end

  def test_withheld_feedback_ends_the_session
    clock = Airplay::FakeDevice::FakeClock.new
    Airplay.clock = clock

    with_control_session(clock: clock, feedback_interval: 2) do |_receiver, session|
      clock.advance(3)

      error = assert_raises(Airplay::TransportError) { session.request("GET", "/info") }

      assert_equal :connect_failed, error.code
      refute session.active?
    end
  end

  def test_volume_maps_linearly_to_decibels
    with_control_session do |receiver, session|
      { 0.0 => -30.0, 0.5 => -15.0, 1.0 => 0.0 }.each do |volume, decibels|
        session.volume = volume
        assert_in_delta decibels, receiver.parameters["volume"], 0.0001
      end
    end
  end

  def test_metadata_is_resent_when_it_changes
    with_control_session do |receiver, session|
      session.metadata = { "title" => "One", "artist" => "A", "album" => "B" }
      assert_equal "One", receiver.parameters.dig("metadata", "title")

      session.metadata = { "title" => "Two", "artist" => "A", "album" => "B" }
      assert_equal "Two", receiver.parameters.dig("metadata", "title")
      assert_equal 2, receiver.exchanges.count { |exchange| exchange.method == "SET_PARAMETER" }
    end
  end

  def test_teardown_stops_frames_and_feedback
    clock = Airplay::FakeDevice::FakeClock.new
    Airplay.clock = clock

    with_control_session(clock: clock, feedback_interval: 2) do |receiver, session|
      frames = receiver.framed_requests
      session.teardown

      assert_equal 1, receiver.exchanges.count { |exchange| exchange.path == "/teardown" }
      assert session.event_channel_lost?
      assert_raises(Airplay::SessionClosedError) { session.request("GET", "/info") }

      clock.advance(10)
      refute session.tick
      sleep 0.02
      assert_equal frames + 1, receiver.framed_requests
    end
  end

  def test_a_401_reauthenticates_on_a_fresh_connection
    Dir.mktmpdir do |dir|
      store = Airplay::Pairing::CredentialStore.new(directory: dir)

      with_receiver(pairing: { pin: "1234", info_body: Airplay::Plist.dump(INFO),
                               faults: { control_401: true } }) do |receiver|
        Airplay.sync do
          setup = Airplay::Pairing::Connection.new(host: "127.0.0.1", port: receiver.port).open
          Airplay::Pairing::Setup.new(code: "1234", transient: false, store: store,
                                      device: "Fake_Apple_TV").run(setup)
          setup.close

          session = Airplay::Control::Session.open(receiver.device, store: store, timing_port: 7001)
          begin
            assert_equal "Fake", session.info["name"]

            first = receiver.exchanges.find { |exchange| exchange.path == "/pair-verify" }.connection
            assert_equal 1, receiver.exchanges.count { |e| e.connection.equal?(first) && e.path == "/info" }
            assert_equal 0, receiver.exchanges.count { |e| e.connection.equal?(first) && e.path == "/setup" }
            assert_equal 3, receiver.connections
          ensure
            session.close
          end
        end
      end
    end
  end

  private

  def with_control_session(info: INFO, setup_body: nil, events: [], clock: nil, feedback_interval: nil)
    Dir.mktmpdir do |dir|
      store = Airplay::Pairing::CredentialStore.new(directory: dir)
      info_body = info.is_a?(String) ? info : Airplay::Plist.dump(info)
      pairing = { pin: "1234", info_body: info_body, setup_body: setup_body, events: events }
      pairing[:clock] = clock if clock
      pairing[:feedback_interval] = feedback_interval if feedback_interval

      with_receiver(pairing: pairing) do |receiver|
        Airplay.sync do
          connection = establish_verified_connection(store, receiver)
          session = Airplay::Control::Session.new(
            connection, timing_port: 7001, event_key: @verify.event_keys.first
          )
          begin
            session.establish
            yield receiver, session
          ensure
            session.close
          end
        end
      end
    end
  end

  def establish_verified_connection(store, receiver)
    setup = Airplay::Pairing::Connection.new(host: "127.0.0.1", port: receiver.port).open
    Airplay::Pairing::Setup.new(code: "1234", transient: false, store: store,
                                device: "Fake_Apple_TV").run(setup)
    setup.close

    connection = Airplay::Pairing::Connection.new(host: "127.0.0.1", port: receiver.port).open
    @verify = Airplay::Pairing::Verify.new(store.read("Fake_Apple_TV")).run(connection)
    connection
  end

  def wait_until(timeout: 2)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
    until yield
      raise "timed out" if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline

      sleep 0.01
    end
  end
end
