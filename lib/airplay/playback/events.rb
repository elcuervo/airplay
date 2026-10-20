require "airplay/plist"

module Airplay
  module Playback
    # Public: Decodes the receiver's event-channel messages into state fields.
    class Events
      STATUS_FOR_NAME = {
        "stopped" => :stopped, "idle" => :stopped, "ended" => :stopped,
        "loading" => :loading, "buffering" => :loading,
        "playing" => :playing, "paused" => :paused
      }.freeze
      STATUS_FOR_CODE = { 1 => :stopped, 2 => :playing, 3 => :paused, 4 => :loading }.freeze
      FIELD_FOR_KEY = {
        "duration" => :duration, "position" => :position, "elapsed" => :position,
        "rate" => :rate, "readyToPlay" => :ready_to_play, "stallCount" => :stall_count,
        "uuid" => :item_id, "itemID" => :item_id, "itemIdentifier" => :item_id,
        "errorCode" => :error_code, "errorDomain" => :error_domain
      }.freeze
      RESPONSE_KINDS = %w[response].freeze

      attr_reader :state, :source

      def initialize(state:, clock: Airplay.clock)
        @state = state
        @clock = clock
        @waiters = {}
        @source = nil
      end

      # Public: Handles one decoded event-channel message; returns the state or nil.
      def handle(message)
        return resolve(message) if response?(message)

        payload = unwrap(message)
        return nil unless payload.is_a?(Hash)

        fields = fields_for(payload)
        return nil if fields.empty?

        @source ||= :events
        @state.update(**fields)
        @state
      end

      # Public: Registers a waiter for a request identifier; the block receives its answer.
      def expect(identifier, &block)
        @waiters[identifier.to_s] = block || proc {}
        block
      end

      def waiting?(identifier)
        @waiters.key?(identifier.to_s)
      end

      private

      def response?(message)
        return false unless message.is_a?(Hash)

        RESPONSE_KINDS.include?((message["type"] || message["kind"]).to_s)
      end

      def resolve(message)
        identifier = message["id"] || message["identifier"] ||
                     dig(message, "params", "requestID") || dig(message, "value", "requestID")
        return nil if identifier.nil?

        waiter = @waiters.delete(identifier.to_s)
        return nil unless waiter

        payload = unwrap(message)
        apply(payload) if payload.is_a?(Hash)
        waiter.call(payload)
        @state
      end

      def apply(payload)
        fields = fields_for(payload)
        @state.update(**fields) unless fields.empty?
      end

      # Internal: Peels value/data wrappers down to the payload that carries state.
      def unwrap(message)
        return nil unless message.is_a?(Hash)

        payload = message["data"].is_a?(Airplay::Plist::Data) ? decode(message["data"]) : message
        return nil unless payload.is_a?(Hash)

        candidate = payload
        state_name = nil
        loop do
          type = candidate["type"].to_s.downcase
          state_name = type if STATUS_FOR_NAME.key?(type)
          if candidate["value"].is_a?(Hash)
            candidate = candidate["value"]
          elsif candidate["params"].is_a?(Hash) &&
                (candidate["params"].key?("state") || candidate["params"].key?("playbackState"))
            candidate = candidate["params"]
          else
            break
          end
        end
        if state_name && candidate.is_a?(Hash) && !candidate.key?("state") &&
           !candidate.key?("playbackState")
          candidate = candidate.merge("state" => state_name)
        end
        candidate
      end

      def decode(data)
        Airplay::Plist.load(data.bytes)
      rescue Airplay::Error
        nil
      end

      def fields_for(payload)
        return {} unless payload.is_a?(Hash)

        fields = {}
        status = status_for(payload["state"] || payload["playbackState"] || payload["status"])
        fields[:status] = status if status
        FIELD_FOR_KEY.each do |key, field|
          fields[field] = payload[key] unless payload[key].nil?
        end
        error = payload["error"]
        if error.is_a?(Hash)
          fields[:error_code] = error["code"]
          fields[:error_domain] = error["domain"]
        end
        fields
      end

      def status_for(value)
        case value
        when Integer then STATUS_FOR_CODE[value]
        when Symbol then State::STATUSES.include?(value) ? value : nil
        when String
          STATUS_FOR_NAME[value.downcase] ||
            (value.match?(/\A\d+\z/) ? STATUS_FOR_CODE[value.to_i] : nil)
        end
      end

      def dig(hash, *keys)
        keys.reduce(hash) { |current, key| current.is_a?(Hash) ? current[key] : nil }
      end
    end
  end
end
