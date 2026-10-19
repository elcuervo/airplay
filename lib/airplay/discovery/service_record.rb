require "airplay/discovery/capabilities"

module Airplay
  module Discovery
    Address = Struct.new(:ip, :family, :interface, :scope, keyword_init: true) do
      def link_local?
        family == :ipv6 && ip.to_s.start_with?("fe80:")
      end

      def to_s
        link_local? && scope ? "#{ip}%#{scope}" : ip.to_s
      end
    end

    # Public: One resolved service instance.
    class ServiceRecord
      attr_reader :name, :display_name, :service_type,
                  :target, :port, :addresses, :txt, :ttl, :capabilities

      def initialize(name:, service_type:, target:, port:, addresses:, txt:, ttl:)
        @name = name
        @display_name = name.include?("@") ? name.split("@", 2).last : name
        @identifier = name.include?("@") ? name.split("@", 2).first : nil
        @service_type = service_type
        @target = target
        @port = port
        @addresses = addresses.freeze
        @txt = txt.freeze
        @ttl = ttl
        @capabilities = Capabilities.new(txt)
      end

      def preferred_address
        addresses.min_by do |address|
          [address.link_local? ? 1 : 0, address.family == :ipv4 ? 0 : 1, address.ip.to_s]
        end
      end

      def advertised_address
        Airplay.configuration.advertised_address || preferred_address&.to_s
      end

      def host
        preferred_address&.ip
      end

      def identifier
        @identifier || capabilities.device_id
      end

      def inspect
        "#<#{self.class} #{display_name.inspect} #{service_type} #{host}:#{port}>"
      end
    end
  end
end
