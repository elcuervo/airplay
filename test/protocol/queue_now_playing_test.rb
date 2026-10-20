require "test_helper"
require "digest"

class QueueNowPlayingTest < Airplay::TestCase
  PROFILE = Airplay::Queue::Profile::TVOS_26_5
  ARTWORK = ("\x89PNG\r\n\x1A\n" + ("a" * 2048)).b

  def test_the_initial_sequence_is_ordered
    with_queue_session do |receiver, session|
      route = build_route(session)
      route.now_playing.item(title: "Clip")

      assert_equal %w[updateNowPlayingInfo updateSupportedCommands updatePlaybackState
                      updatePlaybackClient], receiver.commands.map { |command| command["type"] }
      client = receiver.commands.last.dig("params")
      assert client["bundleIdentifier"]
      assert client["name"]
    ensure
      route&.close
    end
  end

  def test_a_full_push_carries_the_documented_field_set
    with_queue_session do |receiver, session|
      route = build_route(session)
      route.now_playing.item(title: "Clip", artist: "Artist", album: "Album",
                             duration: 12.0, artwork: ARTWORK, artwork_mime: "image/png")

      command = receiver.commands.first
      params = command.dig("params")
      info = params["nowPlayingInfo"]

      assert_equal "updateNowPlayingInfo", command["type"]
      assert_equal "replace", params["mergePolicy"]
      assert_equal({ "title" => "Clip", "artist" => "Artist", "album" => "Album" }, info["text"])
      assert_equal 12.0, info["duration"]
      assert_equal 0.0, info["elapsed"]
      assert_equal 1.0, info["rate"]
      assert_kind_of Time, info["timestamp"]
      assert info["uuid"]
      assert_equal ARTWORK, info["artwork"].bytes
      assert_equal "image/png", info["artworkMimeType"]
      assert_equal Digest::SHA256.hexdigest(ARTWORK), info["artworkIdentifier"]
    ensure
      route&.close
    end
  end

  def test_a_push_without_artwork_omits_the_artwork_keys
    with_queue_session do |receiver, session|
      route = build_route(session)
      route.now_playing.item(title: "Clip")

      info = receiver.commands.first.dig("params", "nowPlayingInfo")
      refute info.key?("artwork")
      refute info.key?("artworkMimeType")
      refute info.key?("artworkIdentifier")
      refute info["text"].key?("artist")
    ensure
      route&.close
    end
  end

  def test_an_unchanged_bundle_is_not_pushed_again
    with_queue_session do |receiver, session|
      route = build_route(session)
      route.now_playing.item(title: "Clip")
      count = receiver.commands.count { |command| command["type"] == "updateNowPlayingInfo" }

      2.times { route.now_playing.update(title: "Clip") }

      assert_equal count,
                   receiver.commands.count { |command| command["type"] == "updateNowPlayingInfo" }
    ensure
      route&.close
    end
  end

  def test_the_item_identifier_is_stable_across_progress_and_fresh_per_item
    with_queue_session do |receiver, session|
      route = build_route(session)
      now = route.now_playing
      now.item(title: "Clip")
      identifier = now.item_id

      now.progress(elapsed: 4.0)
      assert_equal identifier, receiver.commands.last.dig("params", "nowPlayingInfo", "uuid")

      now.item(title: "Other")
      second = now.item_id
      refute_equal identifier, second
      info = receiver.commands.find { |c| c["type"] == "updateNowPlayingInfo" &&
                                          c.dig("params", "nowPlayingInfo", "uuid") == second }
                 .dig("params", "nowPlayingInfo")
      refute info.key?("artwork")
    ensure
      route&.close
    end
  end

  def test_a_seek_is_an_update_without_artwork
    with_queue_session do |receiver, session|
      route = build_route(session)
      route.now_playing.item(title: "Clip", artwork: ARTWORK, artwork_mime: "image/png")
      receiver.commands.clear

      route.now_playing.seek(elapsed: 20.0)

      info = receiver.commands.first
      assert_equal 1, receiver.commands.length
      assert_equal "update", info.dig("params", "mergePolicy")
      assert_equal 20.0, info.dig("params", "nowPlayingInfo", "elapsed")
      refute info.dig("params", "nowPlayingInfo").key?("artwork")
      refute info.dig("params", "nowPlayingInfo").key?("text")
    ensure
      route&.close
    end
  end

  def test_pause_pushes_the_timeline_before_the_state
    with_queue_session do |receiver, session|
      route = build_route(session)
      route.now_playing.item(title: "Clip", artwork: ARTWORK, artwork_mime: "image/png")
      receiver.commands.clear

      route.now_playing.pause

      assert_equal %w[updateNowPlayingInfo updatePlaybackState],
                   receiver.commands.map { |command| command["type"] }
      assert_equal "paused", receiver.commands.last.dig("params", "state")
      assert_equal "update", receiver.commands.first.dig("params", "mergePolicy")
      refute receiver.commands.first.dig("params", "nowPlayingInfo").key?("artwork")
    ensure
      route&.close
    end
  end

  def test_a_rejected_update_form_downgrades_to_full_pushes
    with_queue_session(queue: { reject_update: 400 }) do |receiver, session|
      route = build_route(session)
      route.now_playing.item(title: "Clip", artwork: ARTWORK, artwork_mime: "image/png")
      receiver.commands.clear

      route.now_playing.seek(elapsed: 10.0)
      route.now_playing.seek(elapsed: 20.0)

      forms = receiver.commands.select { |c| c["type"] == "updateNowPlayingInfo" }
                               .map { |c| c.dig("params", "mergePolicy") }
      assert_equal %w[update replace], forms
      assert_equal ARTWORK, receiver.commands.last.dig("params", "nowPlayingInfo", "artwork").bytes
      refute_empty route.now_playing.failures
    ensure
      route&.close
    end
  end

  def test_now_playing_can_be_disabled
    with_queue_session do |receiver, session|
      route = build_route(session, now_playing: false)
      route.now_playing.item(title: "Clip")

      assert_empty receiver.commands
      refute route.now_playing.enabled?
    ensure
      route&.close
    end
  end

  def test_a_rejected_push_does_not_fail_playback
    with_queue_session(queue: { faults: { "updateNowPlayingInfo" => 400 } }) do |_receiver, session|
      route = build_route(session)
      route.now_playing.item(title: "Clip")
      route.play("http://example.com/movie.mp4")

      refute_empty route.now_playing.failures
      assert session.active?
    ensure
      route&.close
    end
  end

  def test_concurrent_pushes_arrive_complete
    with_queue_session do |receiver, session|
      route = build_route(session)
      route.now_playing.item(title: "Clip")
      receiver.commands.clear

      first = Async::Task.current.async { route.now_playing.update(title: "One") }
      second = Async::Task.current.async { route.now_playing.update(title: "Two") }
      first.wait
      second.wait

      titles = receiver.commands.select { |command| command["type"] == "updateNowPlayingInfo" }
                                .map { |command| command.dig("params", "nowPlayingInfo", "text", "title") }
      assert_equal %w[One Two].sort, titles.sort
    ensure
      route&.close
    end
  end

  private

  def build_route(session, now_playing: true)
    Airplay::Player::Queue.new(session: session, profile: PROFILE, media_host: nil,
                               now_playing: now_playing, window: 0.1)
  end
end
