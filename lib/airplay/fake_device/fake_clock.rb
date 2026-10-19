require "airplay/clock"

module Airplay
  module FakeDevice
    # Public: Advanceable clock for tests; no wall-clock sleeps.
    class FakeClock < Airplay::Clock
      def initialize(now: 0.0)
        @now = now
      end

      attr_reader :now

      def sleep(duration)
        @now += duration
      end

      def advance(seconds)
        @now += seconds
      end
    end
  end
end
