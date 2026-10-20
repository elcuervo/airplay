require "test_helper"

class PlaybackStateProtocolTest < Airplay::TestCase
  PROFILE = Airplay::Queue::Profile::TVOS_26_5

  def test_a_nested_event_payload_is_decoded_and_acknowledged
    with_queue_session do |receiver, session|
      state, seen = track_states(session)
      nested = Airplay::Plist.dump("state" => "playing", "duration" => 30.0)
      receiver.push_event("type" => "event", "data" => Airplay::Plist::Data.new(nested))
      wait_until { state.started? }

      assert_equal 30.0, state.duration
      assert_equal 1, receiver.event_acks
      assert_equal [:playing], seen
    end
  end

  def test_a_message_without_a_plist_is_ignored_and_the_channel_stays_open
    with_queue_session do |receiver, session|
      state, seen = track_states(session)

      receiver.push_event_body("this is not a property list")
      receiver.push_state("playing")
      wait_until { state.started? }

      assert_equal [:playing], seen
      refute session.event_channel_lost?
      assert_operator receiver.event_acks, :>=, 2
    end
  end

  def test_the_polled_source_starts_and_ends_a_silent_receiver
    with_queue_session(queue: { playback_info: [:playing, :empty] }) do |_receiver, session|
      clock = Airplay::FakeDevice::FakeClock.new
      state = Airplay::Playback::State.new
      polling = Airplay::Playback::Polling.new(state: state, session: session,
                                               clock: clock, interval: 0)
      monitor = Airplay::Playback::Monitor.new(state: state, polling: polling, clock: clock,
                                                window: 1.0)
      monitor.start

      assert monitor.await_start!
      assert_equal :playing, state.status
      assert_equal 100.0, state.duration

      monitor.wait
      assert_equal :stopped, state.status
      assert state.ended?
      assert_equal :polled, monitor.source
      assert_includes @output.string, "playback.source"
    end
  end

  def test_an_empty_playback_info_answer_means_stopped
    with_queue_session(queue: { playback_info: [:empty] }) do |_receiver, session|
      state = Airplay::Playback::State.new
      polling = Airplay::Playback::Polling.new(state: state, session: session, interval: 0)
      polling.tick

      assert_equal :stopped, state.status
    end
  end

  def test_a_failing_playback_info_is_not_a_state_failure
    with_queue_session(queue: { playback_info: [:error] }) do |_receiver, session|
      state = Airplay::Playback::State.new
      polling = Airplay::Playback::Polling.new(state: state, session: session, interval: 0)

      assert_nil polling.tick
      assert_equal :unknown, state.status
    end
  end

  def test_a_reported_error_object_is_surfaced
    answer = { plist: { "errorCode" => -1, "errorDomain" => "AVFoundation" } }
    with_queue_session(queue: { playback_info: [answer] }) do |_receiver, session|
      state = Airplay::Playback::State.new
      Airplay::Playback::Polling.new(state: state, session: session, interval: 0).tick

      assert_equal(-1, state.error_code)
      assert_equal "AVFoundation", state.error_domain
    end
  end

  def test_a_correlated_snapshot_updates_the_model_once
    with_queue_session(queue: { snapshot: "paused" }) do |receiver, session|
      route = Airplay::Player::Queue.new(session: session, profile: PROFILE, window: 0.1)
      changes = []
      route.state.on_change { |state| changes << state.status }

      route.request_snapshot
      wait_until { route.state.status == :paused }

      assert_equal [:paused], changes
      assert_equal 1, receiver.commands.count { |c| c["type"] == "getPlaybackState" }
    ensure
      route&.close
    end
  end

  def test_an_unmatched_snapshot_answer_is_ignored
    with_queue_session do |receiver, session|
      route = Airplay::Player::Queue.new(session: session, profile: PROFILE, window: 0.1)
      changes = []
      route.state.on_change { |state| changes << state.status }

      receiver.push_event("type" => "response", "id" => "unknown",
                          "value" => { "state" => "playing" })
      route.state.update(status: :stopped)

      assert_empty changes.reject { |status| status == :stopped }
      refute route.state.started?
    ensure
      route&.close
    end
  end

  def test_the_event_and_polled_routes_produce_the_same_model
    event_sequence = []
    event_state = nil
    with_queue_session do |receiver, session|
      state, seen = track_states(session)
      receiver.push_state("playing", "duration" => 100.0, "position" => 5.0,
                                     "rate" => 1.0, "readyToPlay" => true)
      wait_until { state.started? }
      receiver.push_state("stopped")
      wait_until { state.ended? }
      event_sequence = seen
      event_state = state.to_h
    end

    polled_sequence = []
    polled_state = nil
    with_queue_session(queue: { playback_info: [:playing, :empty] }) do |_receiver, session|
      state = Airplay::Playback::State.new
      seen = []
      state.on_change { |current| seen << current.status }
      clock = Airplay::FakeDevice::FakeClock.new
      polling = Airplay::Playback::Polling.new(state: state, session: session,
                                               clock: clock, interval: 0)
      polling.tick
      polling.tick
      polled_sequence = seen
      polled_state = state.to_h
    end

    assert_equal event_sequence, polled_sequence
    assert_equal %i[playing stopped], polled_sequence
    %i[status duration position rate ready_to_play].each do |field|
      assert_equal event_state[field], polled_state[field], field
    end
  end

  private

  def track_states(session)
    state = Airplay::Playback::State.new
    events = Airplay::Playback::Events.new(state: state)
    seen = []
    state.on_change { |current| seen << current.status }
    session.on_event { |event| events.handle(event) }
    [state, seen]
  end
end
