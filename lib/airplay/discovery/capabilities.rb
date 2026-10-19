require "airplay/discovery/version"

module Airplay
  module Discovery
    # Public: Typed view over a receiver's TXT record.
    class Capabilities
      BITS = {
        video: 0,
        photo: 1,
        slideshow: 5,
        screen: 7,
        audio: 9,
        unified_media_control: 38,
        buffered_audio: 40,
        ptp: 41,
        transient_pairing: 43,
        pairing: 46,
        airplay2: 48,
        video_v2: 49
      }.freeze

      FLAGS = {
        pin: 0x8,
        password: 0x80,
        legacy_pairing: 0x200
      }.freeze

      BUFFERED_AUDIO_VERSION = "354.54.6"
      PTP_VERSION = "366"

      attr_reader :txt, :disagreements

      def initialize(txt = nil, effective: nil, authoritative_keys: [], **keywords)
        txt = keywords.merge(txt || {})
        @txt = stringify(txt).freeze
        @effective = stringify(effective || txt).freeze
        @authoritative_keys = authoritative_keys.map(&:to_s).freeze
        @disagreements = @authoritative_keys.select do |key|
          @txt.key?(key) && @txt[key] != @effective[key]
        end.freeze
        @mask = parse_mask(@effective["features"] || @effective["ft"])
        @flags = parse_integer(@effective["sf"] || @effective["flags"])
        @srcvers = Version.parse(@effective["srcvers"])
        @protovers = Version.parse(@effective["protovers"])
        @osvers = Version.parse(@effective["osvers"])
      end

      def mask
        @mask
      end

      def flags
        @flags
      end

      def srcvers
        @srcvers
      end

      def protovers
        @protovers
      end

      def osvers
        @osvers
      end

      def source(field)
        key = KEY_FOR_FIELD[field]
        return(@authoritative_keys.include?(key) ? :authoritative : :txt) if key
        :txt
      end

      def refresh(authoritative)
        incoming = stringify(authoritative)
        Capabilities.new(
          @txt,
          effective: @effective.merge(incoming),
          authoritative_keys: @authoritative_keys + incoming.keys
        )
      end

      def device_id
        @effective["deviceid"]
      end

      def identity
        @effective["pi"] || @effective["psi"]
      end

      def public_key
        @effective["pk"]
      end

      def group_id
        reduce_group_id(@effective["gid"])
      end

      def parent_group_id
        reduce_group_id(@effective["pgid"])
      end

      def tight_sync_id
        @effective["tsid"]
      end

      def group_public_name
        @effective["gpn"]
      end

      def group_leader?
        truthy?(@effective["igl"])
      end

      def group_connected_leader?
        truthy?(@effective["gcgl"])
      end

      def parent_group_connected_leader?
        truthy?(@effective["pgcgl"])
      end

      def groupable?
        !group_id.nil? || !tight_sync_id.nil?
      end

      def acl
        @effective["acl"]
      end

      def act
        @effective["act"]
      end

      def rsf
        @effective["rsf"]
      end

      def restricted_access?
        acl == "1"
      end

      def password_required?
        truthy?(@effective["pw"]) || flag?(FLAGS[:password])
      end

      def pin_required?
        flag?(FLAGS[:pin])
      end

      def legacy_pairing?
        flag?(FLAGS[:legacy_pairing])
      end

      def video?
        bit?(BITS[:video])
      end

      def video_v2?
        bit?(BITS[:video_v2])
      end

      def photo?
        bit?(BITS[:photo])
      end

      def slideshow?
        bit?(BITS[:slideshow])
      end

      def screen?
        bit?(BITS[:screen])
      end

      def audio?
        bit?(BITS[:audio])
      end

      def unified_media_control?
        bit?(BITS[:unified_media_control])
      end

      def pairing?
        bit?(BITS[:pairing])
      end

      def airplay2?
        bit?(BITS[:unified_media_control]) || bit?(BITS[:airplay2])
      end

      def transient_pairing?
        bit?(BITS[:transient_pairing]) || bit?(BITS[:airplay2])
      end

      def buffered_audio?
        bit?(BITS[:buffered_audio]) && version_at_least?(@srcvers, BUFFERED_AUDIO_VERSION)
      end

      def ptp?
        bit?(BITS[:ptp]) && version_at_least?(@srcvers, PTP_VERSION)
      end

      private

      def bit?(position)
        !@mask.nil? && (@mask & (1 << position)) != 0
      end

      def flag?(value)
        !@flags.nil? && (@flags & value) != 0
      end

      def version_at_least?(version, target)
        !version.nil? && version >= Version.parse(target)
      end

      def truthy?(value)
        %w[1 true yes].include?(value.to_s.downcase)
      end

      def reduce_group_id(value)
        return nil if value.nil?

        leading = value.to_s.split("+").first
        leading.nil? || leading.empty? ? nil : leading
      end

      def stringify(hash)
        hash.each_with_object({}) do |(key, value), result|
          result[key.to_s] = value.nil? ? "" : value.to_s
        end
      end

      def parse_mask(value)
        return nil if value.nil?

        parts = value.to_s.split(",")
        case parts.length
        when 1
          parse_hex(parts[0])
        when 2
          low = parse_hex(parts[0])
          high = parse_hex(parts[1])
          low && high ? (high << 32) | low : nil
        end
      end

      def parse_hex(value)
        text = value.to_s.strip
        return nil unless text.match?(/\A0x[0-9a-f]+\z/i)

        Integer(text, 16)
      rescue ArgumentError
        nil
      end

      def parse_integer(value)
        return nil if value.nil?

        text = value.to_s.strip
        return nil unless text.match?(/\A(?:0x[0-9a-f]+|\d+)\z/i)

        Integer(text, 0)
      rescue ArgumentError
        nil
      end

      KEY_FOR_FIELD = {
        mask: "features",
        flags: "sf",
        srcvers: "srcvers",
        protovers: "protovers",
        osvers: "osvers"
      }.freeze
    end
  end
end
