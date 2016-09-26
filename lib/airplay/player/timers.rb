module Airplay
  class Player
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
        @timers.each { |t| t.wakeup }
        @timers = []
      end

      def cancel
        @timers.each { |t| t.kill }
      end
    end
  end
end
