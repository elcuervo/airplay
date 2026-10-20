require "airplay/errors"
require "airplay/status"

module Airplay
  module Playback
    # Public: Drives a state from events, falling back to polling, and bounds startup.
    class Monitor
      DEFAULT_WINDOW = 5.0
      POLL_INTERVAL = 1.0
      TICK = 0.05

      attr_reader :state, :events, :polling, :attempts, :source

      def initialize(state:, events: nil, polling: nil, clock: Airplay.clock,
                     window: DEFAULT_WINDOW)
        @state = state
        @events = events
        @polling = polling
        @clock = clock
        @window = window
        @started_at = nil
        @attempts = 0
        @source = nil
      end

      def started_at
        @started_at
      end

      # Public: Begins the startup window; called once the start sequence was accepted.
      def start
        @started_at = @clock.now
        @attempts = 0
        self
      end

      # Public: Folds one decoded event-channel message into the state.
      def handle_event(message)
        result = @events&.handle(message)
        record_source(:events) if result
        result
      end

      # Public: True once the receiver reported playing, raising after the window.
      def await_start!
        return true if @state.started?

        loop do
          poll_once
          return true if @state.started?

          if @started_at && @clock.now - @started_at >= @window
            Airplay::Status.emit("playback.not_started", attempts: @attempts, window: @window)
            raise Airplay::PlaybackError.new(
              "receiver accepted the play but never reported playback starting",
              code: :playback_not_started
            )
          end
          @clock.sleep(TICK)
        end
      end

      # Public: Waits for the end; a route that cannot observe a start polls to completion.
      def wait(require_start: true)
        if require_start
          await_start!
        else
          poll_once
          return @state if finished?
        end

        until finished?
          poll_once
          break if finished?

          @clock.sleep(TICK)
        end
        @state
      end

      def finished?
        @state.started? ? @state.ended? : @state.status == :stopped
      end

      def poll_once
        return nil unless @polling
        return nil if @source == :events

        @attempts += 1
        result = @polling.tick
        record_source(:polled) if result
        result
      end

      private

      def record_source(source)
        return if @source == source

        @source = source
        Airplay::Status.emit("playback.source", source: source)
      end
    end
  end
end
