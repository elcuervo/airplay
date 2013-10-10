module Airplay::Protocol
  class Timers
    include Enumerable
    extend  Forwardable

    def_delegators :@timers, :each, :size, :empty?

    def initialize
      @timers = []
    end

    def <<(timer)
      @timers << timer
    end

    def reset
      @timers.each { |t| t.reset }
      @timers = []
    end

    def cancel
      @timers.each { |t| t.cancel }
    end
  end
end
