require "airplay/errors"

module Airplay
  module Playback
    # Public: Fallback state source driven by GET /playback-info.
    class Polling
      READY_KEYS = {
        "readyToPlay" => :ready_to_play, "stallCount" => :stall_count,
        "duration" => :duration, "position" => :position, "rate" => :rate,
        "uuid" => :item_id, "itemID" => :item_id
      }.freeze

      attr_reader :source

      def initialize(state:, session:, interval: 1.0, clock: Airplay.clock)
        @state = state
        @session = session
        @interval = interval
        @clock = clock
        @last = nil
        @source = :polled
      end

      def tick
        now = @clock.now
        return nil if @last && now - @last < @interval

        @last = now
        status, payload = @session.playback_info_document
        return nil unless status.is_a?(Integer) && status.between?(200, 299)

        @state.update(**fields_for(payload))
        @state
      end

      private

      def fields_for(payload)
        return { status: :stopped } if payload.nil? || payload.empty?

        fields = { status: status_for(payload) }
        READY_KEYS.each do |key, field|
          fields[field] = payload[key] unless payload[key].nil?
        end
        fields[:error_code] = payload["errorCode"] unless payload["errorCode"].nil?
        fields[:error_domain] = payload["errorDomain"] unless payload["errorDomain"].nil?
        fields
      end

      def status_for(payload)
        if payload["rate"].to_f.zero? && payload.key?("rate") &&
           !payload["duration"].nil? && !payload["position"].nil? &&
           payload["position"].to_f >= payload["duration"].to_f
          return :stopped
        end
        return :paused if payload["rate"].to_f.zero? && payload.key?("rate")
        return :loading if payload["readyToPlay"] == false

        :playing
      end
    end
  end
end
