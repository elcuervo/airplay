require "resolv"

require "airplay/errors"
require "airplay/discovery/cache"
require "airplay/discovery/codec"
require "airplay/discovery/service_record"
require "airplay/discovery/transport"

module Airplay
  module Discovery
    BrowseResult = Struct.new(:records, :reason, keyword_init: true)

    # Public: Browse and resolve AirPlay/RAOP services over multicast DNS.
    class Browser
      QUIET_PERIOD = 0.15
      RETRY_INTERVAL = 0.5

      attr_reader :cache

      def initialize(port: nil, interfaces: nil, families: [:ipv4], clock: nil, cache: nil)
        @port = port || Airplay.configuration.discovery_port
        @interfaces = interfaces || Airplay.configuration.discovery_interfaces
        @families = families
        @clock = clock || Airplay.clock
        @cache = cache || Cache.new(clock: @clock)
        @cancelled = false
        @sockets = []
      end

      def browse(window: nil, families: @families, force: false)
        window ||= Airplay.configuration.discovery_window
        @cancelled = false

        if !force && @cache.fresh?
          return BrowseResult.new(records: @cache.records, reason: :data_available)
        end

        @sockets = Transport.open(port: @port, interfaces: @interfaces, families: families)
        pending = {}
        addresses = Hash.new { |hash, key| hash[key] = [] }
        send_queries

        deadline = monotonic + window
        next_query = monotonic + RETRY_INTERVAL
        first_record_at = nil
        received = false
        reason = :window_elapsed

        loop do
          break if @cancelled

          now = monotonic
          if now >= next_query
            send_queries
            next_query = now + RETRY_INTERVAL
          end

          remaining = deadline - now
          break if remaining <= 0

          @sockets.each do |socket|
            packet = Transport.receive(socket, [remaining, 0.05].min)
            next unless packet

            received = true
            ingest(packet[0], socket, pending, addresses)
          end

          build_records(pending, addresses)
          next unless received
          next if @cache.empty?

          first_record_at ||= monotonic
          if monotonic - first_record_at >= QUIET_PERIOD
            reason = :data_available
            break
          end
        end

        BrowseResult.new(
          records: @cache.records,
          reason: @cancelled ? :cancelled : reason
        )
      rescue IOError, Async::Stop
        BrowseResult.new(records: @cache.records, reason: :cancelled)
      rescue Airplay::Error
        raise
      rescue SystemCallError, SocketError => error
        raise Airplay::TransportError.new(
          "discovery socket failure: #{error.message}", code: :discovery_socket
        )
      ensure
        @sockets.each { |socket| socket.io.close rescue nil }
        @sockets = []
      end

      def cancel!
        @cancelled = true
        @sockets.each { |socket| socket.io.close rescue nil }
      end

      private

      def send_queries
        SERVICE_TYPES.each do |type|
          payload = Codec.query(type)
          @sockets.each { |socket| Transport.send(socket, payload, @port) }
        end
      end

      def ingest(data, socket, pending, addresses)
        message = Codec.decode(data)

        message.resources.each do |resource|
          name = normalize(resource.name)
          payload = resource.data

          if resource.ttl.to_i.zero?
            instance = instance_name(name, payload)
            @cache.remove(instance)
            pending.delete(instance)
            next
          end

          case payload
          when Resolv::DNS::Resource::PTR
            instance = strip_service_type(normalize(payload.name))
            entry = (pending[instance] ||= new_entry)
            entry[:service_type] ||= normalize_type(name)
          when Resolv::DNS::Resource::IN::SRV
            instance = strip_service_type(name)
            entry = (pending[instance] ||= new_entry)
            entry[:target] = normalize(payload.target)
            entry[:port] = payload.port
            entry[:ttl] = resource.ttl
          when Resolv::DNS::Resource::TXT
            instance = strip_service_type(name)
            entry = (pending[instance] ||= new_entry)
            entry[:txt] = Codec.txt(payload.strings)
            entry[:txt_ttl] = resource.ttl
          when Resolv::DNS::Resource::IN::A
            addresses[name] << address_for(payload.address, :ipv4, socket)
          when Resolv::DNS::Resource::IN::AAAA
            addresses[name] << address_for(payload.address, :ipv6, socket)
          end
        end
      rescue Airplay::ProtocolError
        nil
      end

      def build_records(pending, addresses)
        pending.each do |name, entry|
          next unless entry[:service_type] && entry[:target] && entry[:port]

          resolved = (entry[:addresses] || []) + addresses[entry[:target]]
          resolved = resolved.uniq { |address| [address.ip.to_s, address.interface] }
          next if resolved.empty?

          ttl = [entry[:ttl], entry[:txt_ttl]].compact.min || 120
          record = ServiceRecord.new(
            name: name,
            service_type: entry[:service_type],
            target: entry[:target],
            port: entry[:port],
            addresses: resolved,
            txt: entry[:txt] || {},
            ttl: ttl
          )
          @cache.put(record)
        end
      end

      def address_for(ip, family, socket)
        text = ip.to_s
        scope = family == :ipv6 && text.start_with?("fe80:") ? socket.interface : nil
        Address.new(ip: text, family: family, interface: socket.interface, scope: scope)
      end

      def new_entry
        { txt: {}, addresses: [] }
      end

      def normalize(value)
        value.to_s.chomp(".")
      end

      def normalize_type(value)
        "#{normalize(value)}."
      end

      def strip_service_type(value)
        SERVICE_TYPES.each do |type|
          suffix = ".#{type.chomp(".")}"
          return value[0...-suffix.length] if value.end_with?(suffix)
        end
        value
      end

      def instance_name(name, payload)
        value = payload.is_a?(Resolv::DNS::Resource::PTR) ? normalize(payload.name) : name
        strip_service_type(value)
      end

      def monotonic
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end
    end
  end
end
