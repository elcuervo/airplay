require "airplay/errors"

module Airplay
  module Playback
    # Public: Route-independent playback state; unreported fields are unknown.
    class State
      FIELDS = %i[status duration position rate ready_to_play stall_count item_id
                  error_code error_domain].freeze
      STATUSES = %i[unknown stopped loading playing paused].freeze

      attr_reader(*FIELDS)

      def initialize
        @status = :unknown
        @duration = nil
        @position = nil
        @rate = nil
        @ready_to_play = nil
        @stall_count = nil
        @item_id = nil
        @error_code = nil
        @error_domain = nil
        @started = false
        @ended = false
        @listeners = []
      end

      def unknown?(field)
        raise ArgumentError, "unknown field #{field}" unless FIELDS.include?(field)

        public_send(field).nil?
      end

      def started? = @started
      def ended? = @ended

      def on_change(&block)
        @listeners << block
        block
      end

      # Public: Folds reported fields in, returning true when the state changed.
      def update(**fields)
        before = values
        fields.each do |field, value|
          raise ArgumentError, "unknown field #{field}" unless FIELDS.include?(field)

          instance_variable_set("@#{field}", value)
        end
        apply_transition
        return false if values == before

        @listeners.each { |listener| listener.call(self) }
        true
      end

      def values
        FIELDS.to_h { |field| [field, public_send(field)] }
      end

      def to_h
        values.merge(started: @started, ended: @ended)
      end

      private

      def apply_transition
        case @status
        when :playing
          @started = true
          @ended = false
        when :stopped
          @ended = true if @started
        end
      end
    end
  end
end
