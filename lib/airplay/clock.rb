module Airplay
  # Public: Clock seam for timing-sensitive code and tests.
  class Clock
    def now
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end

    def sleep(duration)
      Kernel.sleep(duration)
    end
  end
end
