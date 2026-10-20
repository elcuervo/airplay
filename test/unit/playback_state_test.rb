require "test_helper"

class PlaybackStateTest < Airplay::TestCase
  def test_every_reported_field_is_readable
    state = Airplay::Playback::State.new
    state.update(status: :playing, duration: 120.0, position: 5.0, rate: 1.0,
                 ready_to_play: true, stall_count: 0, item_id: "item-1")

    assert_equal :playing, state.status
    assert_equal 120.0, state.duration
    assert_equal 5.0, state.position
    assert_equal 1.0, state.rate
    assert_equal true, state.ready_to_play
    assert_equal 0, state.stall_count
    assert_equal "item-1", state.item_id
    assert state.started?
  end

  def test_unreported_fields_are_unknown_not_zero
    state = Airplay::Playback::State.new
    state.update(status: :playing)

    assert state.unknown?(:duration)
    assert state.unknown?(:position)
    assert state.unknown?(:rate)
    assert_nil state.duration
  end

  def test_a_repeated_report_is_not_delivered_twice
    state = Airplay::Playback::State.new
    delivered = []
    state.on_change { |current| delivered << current.status }

    3.times { state.update(status: :playing) }

    assert_equal [:playing], delivered
  end

  def test_each_distinct_change_is_delivered_once
    state = Airplay::Playback::State.new
    delivered = []
    state.on_change { |current| delivered << current.status }

    state.update(status: :playing)
    state.update(status: :paused)
    state.update(status: :paused)
    state.update(status: :playing)

    assert_equal %i[playing paused playing], delivered
  end

  def test_receiver_errors_pass_through_verbatim
    state = Airplay::Playback::State.new
    state.update(status: :stopped, error_code: -1, error_domain: "AVFoundation")

    assert_equal(-1, state.error_code)
    assert_equal "AVFoundation", state.error_domain
  end

  def test_load_then_play_is_not_an_end
    state = Airplay::Playback::State.new
    state.update(status: :playing)
    state.update(status: :loading)
    state.update(status: :playing)

    assert state.started?
    refute state.ended?
  end

  def test_stopped_after_playing_ends_the_play
    state = Airplay::Playback::State.new
    state.update(status: :playing)
    state.update(status: :stopped)

    assert state.ended?
    assert_equal :stopped, state.status
  end

  def test_unknown_field_names_are_rejected
    assert_raises(ArgumentError) { Airplay::Playback::State.new.update(bogus: 1) }
    assert_raises(ArgumentError) { Airplay::Playback::State.new.unknown?(:bogus) }
  end
end
