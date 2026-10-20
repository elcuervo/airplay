require "airplay/queue/command"
require "airplay/status"

module Airplay
  module Queue
    # Public: Version-sensitive wire values, selected from the receiver's firmware.
    class Profile
      FIELDS = %i[
        id firmwares sender stream_header channel_identity action_at_item_end
        media_kind client_type commands fields
      ].freeze

      attr_reader(*FIELDS)

      def initialize(id:, firmwares: [], sender:, stream_header:, channel_identity:,
                     action_at_item_end:, media_kind: "file", client_type:,
                     commands: nil, fields: nil)
        @id = id
        @firmwares = Array(firmwares).freeze
        @sender = sender
        @stream_header = stream_header
        @channel_identity = channel_identity
        @action_at_item_end = action_at_item_end
        @media_kind = media_kind
        @client_type = client_type
        @commands = (commands || Command::DEFAULT_COMMANDS).freeze
        @fields = (fields || Command::DEFAULT_FIELDS).freeze
      end

      def firmware?(version)
        text = version.to_s
        return false if text.empty?

        @firmwares.any? { |candidate| text == candidate || text.start_with?("#{candidate}.") }
      end

      DEFAULT = new(
        id: "default",
        sender: "AirPlay/960.13.1",
        stream_header: "x-apple-streamid",
        channel_identity: :sender,
        action_at_item_end: true,
        client_type: "com.apple.airplay.remotectl"
      )

      TVOS_26_5 = new(
        id: "tvos-26.5",
        firmwares: %w[870.14.1],
        sender: "AirPlay/870.14.1",
        stream_header: "x-apple-stream-id",
        channel_identity: :receiver,
        action_at_item_end: true,
        client_type: "com.apple.airplay.remotectl"
      )

      TVOS_18_4 = new(
        id: "tvos-18.4",
        firmwares: %w[550.10],
        sender: "AirPlay/550.10",
        stream_header: "x-apple-stream-id",
        channel_identity: :sender,
        action_at_item_end: false,
        client_type: "com.apple.airplay.remotectl"
      )

      TABLE = [TVOS_26_5, TVOS_18_4, DEFAULT].freeze

      class << self
        # Public: Selects the profile for a reported firmware, logging the decision.
        def select(firmware)
          text = firmware.to_s
          match = TABLE.find { |profile| profile.firmware?(text) }
          reason = if match
                     "firmware #{text.empty? ? 'unknown' : text} selects #{match.id}"
                   else
                     "unknown firmware #{text.empty? ? '(none reported)' : text}; using the default profile"
                   end
          profile = match || DEFAULT
          Airplay::Status.emit("queue.profile", profile: profile.id, firmware: text, reason: reason)
          profile
        end
      end
    end
  end
end
