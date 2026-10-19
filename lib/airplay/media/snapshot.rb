module Airplay
  module Media
    # Public: One /playback-info document, preserving absent keys.
    class Snapshot
      attr_reader :payload, :duration, :position, :rate, :ready_to_play,
                  :seekable, :loaded, :buffering

      def initialize(payload)
        @payload = payload || {}
        @duration = @payload["duration"]
        @position = @payload["position"]
        @rate = @payload["rate"]
        @ready_to_play = @payload["readyToPlay"]
        @buffering = !(@payload["bufferAhead"].nil? && @payload["bufferFull"].nil?)
        @seekable = ranges(@payload["seekableTimeRanges"])
        @loaded = ranges(@payload["loadedTimeRanges"])
      end

      def stopped?
        @rate.nil? && @duration.nil?
      end

      def playing?
        !stopped? && @rate.to_f.positive?
      end

      def played?
        return false if @duration.nil? || @position.nil?

        @duration.to_f.positive? && @position.to_f >= @duration.to_f &&
          (@rate.nil? || @rate.to_f.zero?)
      end

      private

      def ranges(value)
        Array(value).map do |entry|
          if entry.is_a?(Hash)
            [entry["start"].to_f, entry["duration"].to_f]
          else
            [entry.to_f, 0.0]
          end
        end
      end
    end
  end
end
