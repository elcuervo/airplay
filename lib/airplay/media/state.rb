require "airplay/errors"

module Airplay
  module Media
    # Public: Declared playback transition table.
    class State
      STATES = %i[stopped loading playing paused played].freeze
      TRANSITIONS = {
        stopped: %i[loading stopped played],
        loading: %i[playing paused stopped played],
        playing: %i[paused stopped played],
        paused: %i[playing stopped played],
        played: %i[loading stopped played]
      }.freeze

      attr_reader :current

      def initialize
        @current = :stopped
      end

      def handle(snapshot)
        target =
          if snapshot.played?
            :played
          elsif snapshot.stopped?
            :stopped
          elsif snapshot.rate.to_f.zero?
            :paused
          elsif %i[stopped played].include?(@current) || snapshot.ready_to_play == false
            :loading
          else
            :playing
          end

        apply(target)
      end

      def apply(target)
        return @current if target == @current
        unless TRANSITIONS.fetch(@current, []).include?(target)
          raise Airplay::PlaybackError.new("illegal transition #{@current} -> #{target}",
                                           code: :playback_error)
        end

        @current = target
      end
    end
  end
end
