require "test_helper"
require "airplay/clock"

class ClockTest < Airplay::TestCase
  def test_system_clock_advances
    clock = Airplay::Clock.new

    assert_operator clock.now, :>, 0
  end

  def test_fake_clock_advances_without_wall_clock_sleep
    clock = Airplay::FakeDevice::FakeClock.new
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    clock.sleep(3_600)
    clock.advance(60)

    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
    assert_equal 3_660, clock.now
    assert_operator elapsed, :<, 0.1
  end
end
