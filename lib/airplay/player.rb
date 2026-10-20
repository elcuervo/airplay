require "socket"

require "airplay/control/session"
require "airplay/errors"
require "airplay/pairing/credential_store"
require "airplay/player/legacy"
require "airplay/player/queue"
require "airplay/playback/monitor"
require "airplay/status"

module Airplay
  # Public: Picks the route from capabilities and hands the media to it.
  module Player
    Decision = Struct.new(:route, :reason, :firmware, :profile, keyword_init: true)

    class << self
      # Public: Decides the playback route without touching the network.
      def decide(capabilities, force_legacy: false)
        if force_legacy
          return Decision.new(route: :legacy, reason: "forced by the legacy option")
        end
        if capabilities.nil?
          return Decision.new(route: :legacy, reason: "no capability model is available")
        end

        firmware = capabilities.srcvers&.to_s
        if !capabilities.video_v2?
          return Decision.new(route: :legacy, firmware: firmware,
                              reason: "the receiver does not report modern video control")
        end
        if (firmware.nil? || firmware.empty?) && Airplay.configuration.conservative_route
          return Decision.new(route: :legacy, firmware: firmware,
                              reason: "the firmware is unknown and the conservative policy is in force")
        end

        Decision.new(route: :queue, firmware: firmware,
                     reason: "the receiver reports modern video control on firmware #{firmware}",
                     profile: Airplay::Queue::Profile.select(firmware))
      end

      # Public: Opens a player on the decided route; closes it when the block returns.
      def open(device, capabilities: nil, force_legacy: false, store: nil, now_playing: nil,
               media_host: :default, window: nil, password: nil, base_url: nil, &block)
        raise ArgumentError, "block required" unless block

        decision = decide(capabilities, force_legacy: force_legacy)
        Airplay::Status.emit("player.route", route: decision.route, reason: decision.reason,
                                            firmware: decision.firmware,
                                            profile: decision.profile&.id)

        player = if decision.route == :queue
                   open_queue(device, capabilities, decision, store, now_playing, media_host, window)
                 else
                   open_legacy(device, capabilities, decision, password, base_url)
                 end
        begin
          yield player
        ensure
          player.close
        end
      rescue Airplay::Error => error
        error.emit!
        raise
      end

      # Public: The address a receiver can use to fetch local media.
      def media_host(explicit = :default)
        return explicit unless explicit == :default

        Airplay.configuration.advertised_address ||
          Socket.ip_address_list.find { |address| address.ipv4? && !address.ipv4_loopback? }&.ip_address
      end

      private

      def open_queue(device, capabilities, decision, store, now_playing, media_host, window)
        session = Airplay::Control::Session.open(
          device,
          store: store || Airplay::Pairing::CredentialStore.new,
          timing_port: Airplay.configuration.timing_port,
          capabilities: capabilities
        )
        begin
          session.record
        rescue Airplay::Error
          session.close
          raise
        end

        Player::Queue.new(
          session: session,
          profile: decision.profile,
          now_playing: now_playing.nil? ? Airplay.configuration.now_playing : now_playing,
          media_host: self.media_host(media_host),
          window: window || Playback::Monitor::DEFAULT_WINDOW,
          decision: decision
        )
      end

      def open_legacy(device, capabilities, decision, password, base_url)
        session = Airplay::Session.new(device, capabilities: capabilities, legacy: true,
                                              password: password, base_url: base_url)
        Player::Legacy.new(session: session, decision: decision)
      rescue Airplay::Error
        session&.close
        raise
      end
    end
  end
end
