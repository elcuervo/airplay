require "test_helper"

class QueueTransportTest < Airplay::TestCase
  PROFILE = Airplay::Queue::Profile::TVOS_26_5
  URL = "http://example.com/movie.mp4"

  def test_pause_and_resume_are_rate_commands
    with_queue_session do |receiver, session|
      route = build_route(session)
      route.play(URL)
      route.pause
      route.resume

      rates = receiver.commands.select { |command| command["type"] == "setRate" }
                               .map { |command| command.dig("params", "rate") }
      assert_equal [1.0, 0.0, 1.0], rates
      refute(receiver.exchanges.any? { |exchange| exchange.path == "/rate" })
    ensure
      route&.close
    end
  end

  def test_stop_ends_playback_and_leaves_the_session_usable
    with_queue_session do |receiver, session|
      route = build_route(session)
      route.play(URL)
      connections = receiver.connections
      route.stop

      types = receiver.commands.map { |command| command["type"] }
      assert_equal %w[insertPlayQueueItem setProperty setProperty setRate setRate
                      removePlayQueueItem], types
      removed = receiver.commands.last.dig("params", "uuid")
      assert_equal removed, receiver.commands.first.dig("params", "uuid")

      route.play("http://example.com/second.mp4")
      assert_equal 2, receiver.commands.count { |command| command["type"] == "insertPlayQueueItem" }
      assert_equal connections, receiver.connections
    ensure
      route&.close
    end
  end

  def test_seek_carries_the_position_for_the_current_item
    with_queue_session do |receiver, session|
      route = build_route(session)
      route.play(URL)
      route.seek(30.0)

      seek = receiver.commands.find { |command| command["type"] == "seekToTime" }
      assert_equal route.item_id, seek.dig("params", "uuid")
      assert_equal 30.0, seek.dig("params", "position")
      refute(receiver.exchanges.any? { |exchange| %w[/scrub].include?(exchange.path) })

      # The reported position follows the receiver, never the requested value.
      assert_nil route.state.position
      receiver.push_state("playing", "position" => 30.5)
      wait_until { route.state.position == 30.5 }
      assert_equal 30.5, route.state.position
    ensure
      route&.close
    end
  end

  def test_a_non_unit_rate_is_applied_and_then_reported_by_the_receiver
    with_queue_session do |receiver, session|
      route = build_route(session)
      route.play(URL)
      route.rate(4.0)

      sent = receiver.commands.select { |command| command["type"] == "setRate" }.last
      assert_equal 4.0, sent.dig("params", "rate")
      assert_nil route.state.rate

      receiver.push_state("playing", "rate" => 4.0)
      wait_until { route.state.rate == 4.0 }
      assert_equal 4.0, route.state.rate
    ensure
      route&.close
    end
  end

  def test_stop_pushes_state_only_when_now_playing_is_active
    with_queue_session do |receiver, session|
      route = build_route(session)
      route.play(URL)
      route.now_playing.item(title: "Clip", artwork: "art", artwork_mime: "image/png")
      receiver.commands.clear
      route.stop

      stop_pushes = receiver.commands.select do |command|
        command["type"] == "updatePlaybackState"
      end
      assert_equal ["stopped"], stop_pushes.map { |command| command.dig("params", "state") }
      refute(receiver.commands.any? { |command| command["type"] == "updateNowPlayingInfo" })
    ensure
      route&.close
    end
  end

  private

  def build_route(session, profile: PROFILE)
    Airplay::Player::Queue.new(session: session, profile: profile, media_host: nil, window: 0.1)
  end
end
