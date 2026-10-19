require "test_helper"

class MediaValuesTest < Minitest::Test
  def test_type_table_and_compatibility
    assert_equal "video/quicktime", Airplay::Media.type_for("movie.mov")
    assert_equal "video/mp4", Airplay::Media.type_for("MOVIE.MP4")
    assert_equal "application/octet-stream", Airplay::Media.type_for("mystery.zzz")
    assert_equal "application/octet-stream", Airplay::Media.type_for("no-extension")

    assert Airplay::Media.compatible?("movie.mov")
    assert Airplay::Media.image?("photo.png")
    refute Airplay::Media.compatible?("notes.txt")
  end

  def test_playlist_navigation_wraps_and_reports_empty
    playlist = Airplay::Media::Playlist.new
    assert playlist.empty?
    assert_nil playlist.next_item

    first = Airplay::Media::Media.new(url: "http://a/1")
    second = Airplay::Media::Media.new(url: "http://a/2")
    playlist << first << second

    assert_equal second, playlist.next_item
    assert_equal first, playlist.next_item
    assert_equal second, playlist.previous
    assert_equal second, playlist.use(1)
    assert_equal second, playlist.current

    media = Airplay::Media::Media.new(source: "movie.mov")
    assert media.local?
    assert media.compatible?
  end

  def test_snapshot_semantics
    empty = Airplay::Media::Snapshot.new({})
    assert empty.stopped?
    refute empty.playing?
    assert_nil empty.duration

    rate_only = Airplay::Media::Snapshot.new("rate" => 1)
    refute rate_only.stopped?
    assert rate_only.playing?
    assert_nil rate_only.duration

    full = Airplay::Media::Snapshot.new(
      "duration" => 10, "position" => 4, "rate" => 1, "readyToPlay" => true,
      "seekableTimeRanges" => [{ "start" => 0, "duration" => 10 }]
    )
    assert_equal 10.0, full.duration
    assert_equal [[0.0, 10.0]], full.seekable
    refute full.played?

    done = Airplay::Media::Snapshot.new("duration" => 10, "position" => 10, "rate" => 0)
    assert done.played?
  end

  def test_state_transitions_and_illegal_transitions
    state = Airplay::Media::State.new

    assert_equal :loading, state.handle(Airplay::Media::Snapshot.new("rate" => 1))
    assert_equal :playing, state.handle(Airplay::Media::Snapshot.new("rate" => 1, "duration" => 10, "position" => 1))
    assert_equal :paused, state.handle(Airplay::Media::Snapshot.new("rate" => 0, "duration" => 10, "position" => 1))
    assert_equal :playing, state.handle(Airplay::Media::Snapshot.new("rate" => 1, "duration" => 10, "position" => 2))
    assert_equal :played, state.handle(Airplay::Media::Snapshot.new("rate" => 0, "duration" => 10, "position" => 10))
    assert_equal :loading, state.handle(Airplay::Media::Snapshot.new("rate" => 1))

    fresh = Airplay::Media::State.new
    assert_raises(Airplay::PlaybackError) { fresh.apply(:paused) }

    fresh.apply(:loading)
    fresh.apply(:played)
    assert_raises(Airplay::PlaybackError) { fresh.apply(:paused) }
  end
end
