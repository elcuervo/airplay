require "test_helper"
require "json"
require "tmpdir"

class QueueHarnessTest < Airplay::TestCase
  PROFILE = Airplay::Queue::Profile::TVOS_26_5

  def test_play_queue_mode_records_the_stream_and_commands
    with_queue_session do |receiver, session|
      session.register_control_stream(profile: PROFILE)
      session.command({ "type" => "insertPlayQueueItem", "params" => { "uuid" => "item-1" } },
                      stream_id: session.stream_id, profile: PROFILE)

      setup = receiver.queue_exchanges.find do |exchange|
        exchange.path == "/setup" && exchange.plist.is_a?(Hash) && exchange.plist["streams"]
      end
      command = receiver.queue_exchanges.find { |exchange| exchange.path == "/command" }

      assert_equal 130, setup.plist["streams"].first["type"]
      assert_equal 1, setup.plist["streams"].first["controlType"]
      assert_equal 77, session.stream_id
      assert_equal "POST", command.method
      assert_equal "insertPlayQueueItem", command.command["type"]
      assert_equal "item-1", command.command["params"]["uuid"]
      assert_equal session.stream_id.to_s, command.headers[PROFILE.stream_header]
      assert_equal PROFILE.sender, command.headers["user-agent"]
    end
  end

  def test_expectation_lists_pass_in_order
    with_queue_session do |receiver, session|
      receiver.expect_requests([
        { method: "POST", path: "/record" },
        { method: "POST", path: "/command", command: { "type" => "setRate",
                                                      "params" => { "rate" => 1.0 } } }
      ])

      session.record
      session.command({ "type" => "setRate", "params" => { "rate" => 1.0 } },
                      stream_id: session.stream_id, profile: PROFILE)

      assert receiver.verify_expectations!
    end
  end

  def test_expectation_lists_fail_at_the_first_divergence
    with_queue_session do |receiver, session|
      receiver.expect_requests([
        { method: "POST", path: "/command", command: { "type" => "setRate" } },
        { method: "POST", path: "/command", command: { "type" => "setProperty" } }
      ])

      session.command({ "type" => "setProperty", "params" => {} },
                      stream_id: session.stream_id, profile: PROFILE)
      session.command({ "type" => "setRate", "params" => {} },
                      stream_id: session.stream_id, profile: PROFILE)

      error = assert_raises(Airplay::FakeDevice::QueueMode::ExpectationError) do
        receiver.verify_expectations!
      end
      assert_includes error.message, "position 1"
      assert_includes error.message, "setProperty"
    end
  end

  def test_expectation_lists_report_extra_requests
    with_queue_session do |receiver, session|
      receiver.expect_requests([{ method: "POST", path: "/record" }])
      session.record
      session.command({ "type" => "setRate", "params" => { "rate" => 1.0 } },
                      stream_id: session.stream_id, profile: PROFILE)

      error = assert_raises(Airplay::FakeDevice::QueueMode::ExpectationError) do
        receiver.verify_expectations!
      end
      assert_includes error.message, "unexpected request"
      assert_includes error.message, "setRate"
    end
  end

  def test_a_bare_command_body_is_refused
    with_queue_session do |receiver, session|
      bare = session.request("POST", "/command",
                             body: Airplay::Plist.dump("type" => "setRate",
                                                      "params" => { "rate" => 1.0 }),
                             headers: { "content-type" => "application/x-apple-binary-plist" })
      assert_equal 400, bare.status

      nested = session.command({ "type" => "setRate", "params" => { "rate" => 1.0 } },
                               stream_id: session.stream_id, profile: PROFILE)
      assert_equal 200, nested.status
    end
  end

  def test_scripted_transitions_are_observed_by_the_sender
    with_queue_session do |receiver, session|
      state, seen = track_states(session)
      receiver.script(:replacement)
      wait_until { seen.length >= 3 }

      assert_equal %i[playing loading playing], seen.first(3)
      assert state.started?
      refute state.ended?
    end
  end

  def test_the_paused_script_is_observed
    with_queue_session do |receiver, session|
      state, seen = track_states(session)
      receiver.script(:paused)
      wait_until { seen.include?(:paused) }

      assert_equal %i[playing paused], seen
      refute state.ended?
    end
  end

  def test_the_stopped_script_ends_playback
    with_queue_session do |receiver, session|
      state, seen = track_states(session)
      receiver.script(:stopped)
      wait_until { state.ended? }

      assert_equal %i[playing stopped], seen
    end
  end

  def test_a_receiver_that_never_transitions_fails_the_startup_window
    with_queue_session do |receiver, session|
      state = Airplay::Playback::State.new
      polling = Airplay::Playback::Polling.new(state: state, session: session,
                                               clock: Airplay.clock, interval: 0.01)
      monitor = Airplay::Playback::Monitor.new(state: state, polling: polling,
                                               clock: Airplay.clock, window: 0.1)
      monitor.start

      receiver.script(:none)
      error = assert_raises(Airplay::PlaybackError) do
        monitor.await_start!
      end

      assert_equal :playback_not_started, error.code
      assert_operator monitor.attempts, :>=, 1
    end
  end

  def test_scripted_playback_info_answers_are_consumed_in_order
    with_queue_session(queue: { playback_info: [:playing, :empty, :error] }) do |_receiver, session|
      first = session.playback_info
      assert_equal 200, first[0]
      assert_equal 1.0, first[1]["rate"]

      second = session.playback_info
      assert_equal 200, second[0]
      assert_equal({}, second[1])

      third = session.playback_info
      assert_equal 500, third[0]
    end
  end

  def test_transient_500_fault_recovers_on_the_third_attempt
    fault = { status: 500, times: 2 }
    with_queue_session(queue: { faults: { "setRate" => fault } }) do |receiver, session|
      client = Airplay::Queue::Client.new(session: session, profile: PROFILE,
                                          stream_id: session.stream_id)
      response = client.command(:rate, { "rate" => 1.0 }, retryable: true)

      assert_equal 200, response.status
      assert_equal 3, receiver.commands.count { |command| command["type"] == "setRate" }
    end
  end

  def test_a_401_maps_to_auth_required_without_a_retry
    with_queue_session(queue: { faults: { "setRate" => 401 } }) do |receiver, session|
      client = Airplay::Queue::Client.new(session: session, profile: PROFILE,
                                          stream_id: session.stream_id)
      error = assert_raises(Airplay::AuthRequiredError) do
        client.command(:rate, { "rate" => 1.0 }, retryable: true)
      end

      assert_equal :auth_required, error.code
      assert_equal 1, receiver.commands.length
    end
  end

  def test_a_403_maps_to_auth_failed
    with_queue_session(queue: { faults: { "setRate" => 403 } }) do |_receiver, session|
      client = Airplay::Queue::Client.new(session: session, profile: PROFILE,
                                          stream_id: session.stream_id)
      error = assert_raises(Airplay::AuthFailedError) do
        client.command(:rate, { "rate" => 1.0 })
      end

      assert_equal :auth_failed, error.code
    end
  end

  def test_a_refused_control_stream_names_the_receiver_status
    with_queue_session(queue: { refuse_stream: true, stream_status: 403 }) do |receiver, session|
      error = assert_raises(Airplay::ProtocolError) do
        session.register_control_stream(profile: PROFILE)
      end

      assert_equal :control_stream, error.code
      assert_equal 403, error.status
      assert_empty receiver.commands
      assert_empty(receiver.exchanges.select { |exchange| exchange.path == "/play" })
    end
  end

  def test_a_failure_after_the_insert_records_exactly_one_insert
    with_queue_session(queue: { faults: { after_insert: 500 } }) do |receiver, session|
      route = build_route(session)
      error = assert_raises(Airplay::ProtocolError) do
        route.play("http://example.com/movie.mp4")
      end

      assert_equal 500, error.status
      assert_equal 1, receiver.commands.count { |command| command["type"] == "insertPlayQueueItem" }
      assert_equal %w[insertPlayQueueItem setProperty], receiver.commands.map { |c| c["type"] }
    end
  end

  def test_the_strict_order_knob_reports_a_connection_failure
    with_queue_session(queue: { strict_order: true }) do |_receiver, session|
      client = Airplay::Queue::Client.new(session: session, profile: PROFILE,
                                          stream_id: session.stream_id)
      error = assert_raises(Airplay::TransportError) do
        client.command(:rate, { "rate" => 1.0 })
      end

      assert_equal :connect_failed, error.code
    end
  end

  def test_fixtures_carry_provenance_and_decode_their_nested_payload
    Dir[File.expand_path("../fixtures/queue/*.json", __dir__)].each do |path|
      fixture = JSON.parse(File.read(path))
      refute_nil fixture["provenance"], "#{path} has no provenance"
      assert fixture["provenance"]["reference"]
      assert fixture["provenance"]["firmware"]

      assert_operator fixture["commands"].length, :>=, 3
      fixture["commands"].each { |command| assert command["type"] }

      insert = Airplay::Plist.load(File.binread(File.expand_path("../fixtures/queue/insert.bplist", __dir__)))
      assert_equal insert, fixture["commands"].first
    end
  end

  def test_the_committed_insert_fixture_is_the_bytes_the_sender_emits
    expected = Airplay::Plist.load(File.binread(File.expand_path("../fixtures/queue/insert.bplist", __dir__)))
    with_queue_session do |receiver, session|
      command = expected
      session.command(command, stream_id: session.stream_id, profile: PROFILE)
      body = receiver.exchanges.find { |exchange| exchange.path == "/command" }.body

      assert_equal Airplay::Plist.load(body)["command"].bytes, Airplay::Plist.dump(command)
    end
  end

  def test_the_media_fetch_client_serves_the_handed_url_with_ranges
    Dir.mktmpdir do |dir|
      path = File.join(dir, "clip.mp4")
      File.binwrite(path, "0123456789abcdef")

      with_queue_session do |receiver, session|
        route = build_route(session, media_host: "127.0.0.1")
        route.play(path)
        url = receiver.commands.first["params"]["url"]

        full = receiver.fetch_media(url)
        assert_equal 200, full.status
        assert_equal "video/mp4", full.headers["content-type"].to_s
        assert_equal 16, full.body.bytesize

        partial = receiver.fetch_media(url, range: "bytes=4-7")
        assert_equal 206, partial.status
        assert_equal "bytes 4-7/16", partial.headers["content-range"].to_s
        assert_equal "4567", partial.body
      ensure
        route&.close
      end
    end
  end

  def test_a_local_file_without_a_reachable_address_fails_typed
    Dir.mktmpdir do |dir|
      path = File.join(dir, "clip.mp4")
      File.binwrite(path, "data")

      with_queue_session do |receiver, session|
        route = build_route(session, media_host: nil)
        error = assert_raises(Airplay::PlaybackError) { route.play(path) }

        assert_equal :unusable_media_address, error.code
        assert_empty receiver.commands
      ensure
        route&.close
      end
    end
  end

  def test_remote_media_is_handed_over_unchanged
    with_queue_session do |receiver, session|
      route = build_route(session, media_host: "127.0.0.1")
      url = "https://example.com/playlist.m3u8"
      route.play(url)

      assert_equal url, receiver.commands.first.dig("params", "url")
      assert_equal true, receiver.commands.first.dig("params", "secure")
      assert_empty receiver.media_fetches
    ensure
      route&.close
    end
  end

  def test_the_handed_url_is_withdrawn_when_the_session_closes
    Dir.mktmpdir do |dir|
      path = File.join(dir, "clip.mp4")
      File.binwrite(path, "0123456789")

      with_queue_session do |receiver, session|
        route = build_route(session, media_host: "127.0.0.1")
        route.play(path)
        url = receiver.commands.first.dig("params", "url")

        assert_equal 200, receiver.fetch_media(url).status
        assert_equal 206, receiver.fetch_media(url, range: "bytes=2-4").status

        route.close
        failed = receiver.fetch_media(url)
        refute_equal 200, failed.status
        assert failed.error || !failed.status.between?(200, 299)
      end
    end
  end

  def test_a_failed_fetch_is_recorded_not_raised
    with_queue_session do |receiver, _session|
      record = receiver.fetch_media("http://127.0.0.1:1/not-served.mp4")

      refute_nil record.error
      assert_equal 1, receiver.media_fetches.length
    end
  end

  private

  def build_route(session, media_host: nil)
    Airplay::Player::Queue.new(session: session, profile: PROFILE, media_host: media_host,
                               window: 0.1)
  end

  def track_states(session)
    state = Airplay::Playback::State.new
    events = Airplay::Playback::Events.new(state: state)
    seen = []
    state.on_change { |current| seen << current.status }
    session.on_event { |event| events.handle(event) }
    [state, seen]
  end
end
