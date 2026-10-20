require "airplay/errors"
require "airplay/media"
require "airplay/playback/monitor"
require "airplay/playback/polling"
require "airplay/playback/state"

module Airplay
  module Player
    # Public: The legacy POST /play route, kept for receivers without the queue.
    class Legacy
      ROUTE = :legacy

      attr_reader :session, :state, :monitor, :decision

      def initialize(session:, clock: Airplay.clock, decision: nil)
        @session = session
        @state = Playback::State.new
        @polling = Playback::Polling.new(state: @state, session: session, clock: clock)
        @monitor = Playback::Monitor.new(state: @state, polling: @polling, clock: clock)
        @items = []
        @index = -1
        @decision = decision
      end

      def now_playing
        nil
      end

      def media_server
        nil
      end

      def play(media, position: 0.0)
        url = media.is_a?(Airplay::Media::Media) ? (media.url || media.source) : media.to_s
        @session.play(url, position: position)
        @items << url
        @index = @items.length - 1
        @monitor.start
        url
      end

      def pause
        @session.rate(0)
      end

      def resume
        @session.rate(1)
      end

      def stop
        @session.stop
      end

      def seek(position)
        @session.scrub(position)
      end

      def rate(value)
        @session.rate(value)
      end

      def next
        navigate(1)
      end

      def previous
        navigate(-1)
      end

      def wait(require_start: false, &block)
        @state.on_change(&block) if block
        @monitor.wait(require_start: require_start)
      end

      def close
        @session.close
      end

      private

      def navigate(offset)
        return nil if @items.empty?

        @index = (@index + offset) % @items.length
        play(@items[@index])
        @items[@index]
      end
    end
  end
end
