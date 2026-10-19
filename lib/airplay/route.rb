require "airplay/errors"
require "airplay/status"

module Airplay
  # Public: The route a device is driven over, decided from capabilities alone.
  module Route
    NATIVE = :airplay2
    LEGACY = :airplay1
    RAOP = :raop

    BITS = {
      video: 0,
      photo: 1,
      audio: 9,
      unified_media_control: 38,
      buffered_audio: 40,
      ptp: 41,
      pairing: 46,
      airplay2: 48,
      video_v2: 49
    }.freeze

    FLAGS = {
      pin: 0x8,
      password: 0x80,
      legacy_pairing: 0x200
    }.freeze

    Decision = Struct.new(:route, :source, :plan, :timing, :stream, :video, :pin_required,
                          keyword_init: true)

    # Internal: Normalized view over a device record or capability hash.
    class Input
      attr_reader :features, :flags

      def initialize(record)
        @features = integer(record[:features] || record["features"])
        @flags = integer(record[:flags] || record["flags"] || record["sf"])
        @password = truthy?(record[:password] || record["password"])
        @password_required = truthy?(record[:pw] || record["pw"]) || flag?(:password)
        @credentials = truthy?(record[:credentials] || record["credentials"])
        @raop = truthy?(record[:raop] || record["raop"])
      end

      def bit?(name)
        position = BITS.fetch(name)
        (@features & (1 << position)) != 0
      end

      def flag?(name)
        (@flags & FLAGS.fetch(name)) != 0
      end

      def airplay2?
        bit?(:unified_media_control) || bit?(:airplay2)
      end

      def pairing?
        bit?(:pairing)
      end

      def legacy_video?
        bit?(:video) || bit?(:photo)
      end

      def credentials? = @credentials
      def raop? = @raop
      def password? = @password
      def password_required? = @password_required

      private

      def integer(value)
        return 0 if value.nil?

        value.is_a?(Integer) ? value : Integer(value.to_s, 0)
      rescue ArgumentError
        0
      end

      def truthy?(value)
        return false if value.nil? || value == false
        return true if value == true

        !value.to_s.empty?
      end
    end

    # Public: Ordered rows; the first matching row owns the route.
    ROWS = [
      {
        name: :legacy_pairing,
        match: ->(input) { input.flag?(:legacy_pairing) },
        route: LEGACY,
        plan: [:legacy_auth]
      },
      {
        name: :native_paired,
        match: ->(input) { input.airplay2? && input.pairing? && input.credentials? },
        route: NATIVE,
        plan: %i[pair_verify info setup]
      },
      {
        name: :native_unpaired,
        match: ->(input) { input.airplay2? && input.pairing? },
        route: NATIVE,
        plan: %i[pair_setup info setup]
      },
      {
        name: :legacy_video,
        match: ->(input) { input.legacy_video? },
        route: LEGACY,
        plan: [:legacy_auth]
      },
      {
        name: :raop,
        match: ->(input) { input.raop? },
        route: RAOP,
        plan: [:raop]
      }
    ].freeze

    class << self
      # Public: Decides the route without touching the network.
      def decide(record, override: nil)
        input = Input.new(record)
        if input.password_required? && !input.password?
          raise Airplay::AuthRequiredError.new("this device requires a password", code: :auth_required)
        end

        return override(input, override) if override

        row = ROWS.find { |candidate| candidate[:match].call(input) }
        build(input, row ? row[:route] : LEGACY, :capabilities, row ? row[:plan] : [:legacy_auth])
      end

      private

      def override(input, value)
        route = normalize(value)
        if route == NATIVE && !(input.airplay2? && input.pairing?)
          raise Airplay::UnsupportedError.new(
            "AirPlay 2 native needs the HK pairing bit", code: :unsupported_feature
          )
        end

        plan = case route
               when NATIVE then input.credentials? ? %i[pair_verify info setup] : %i[pair_setup info setup]
               when LEGACY then [:legacy_auth]
               when RAOP then [:raop]
               end

        build(input, route, :override, plan)
      end

      def normalize(value)
        case value.to_s
        when "airplay2", "native" then NATIVE
        when "airplay1", "legacy" then LEGACY
        when "raop" then RAOP
        else
          raise Airplay::UnsupportedError.new("unknown route #{value.inspect}", code: :unsupported_feature)
        end
      end

      def build(input, route, source, plan)
        Airplay::Status.emit("route.decide", route: route, source: source)
        Decision.new(
          route: route,
          source: source,
          plan: plan,
          timing: input.bit?(:ptp) ? :ptp : :ntp,
          stream: input.bit?(:buffered_audio) ? :buffered : :realtime,
          video: input.bit?(:video_v2) ? :v2 : :legacy,
          pin_required: input.flag?(:pin)
        )
      end
    end
  end
end
