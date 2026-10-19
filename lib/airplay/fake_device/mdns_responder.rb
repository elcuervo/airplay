require "resolv"

require "airplay/discovery/codec"
require "airplay/discovery/transport"

module Airplay
  module FakeDevice
    # Public: In-process mDNS responder used by the discovery protocol tests.
    class MDNSResponder
      Instance = Struct.new(
        :name, :type, :target, :port, :txt, :ttl, :address, :address6,
        :fault, :drop, :conflicting_txt,
        keyword_init: true
      )
      Received = Struct.new(:source, :message, :raw, keyword_init: true)

      DEFAULTS = {
        type: "_airplay._tcp.local.",
        target: "fake.local.",
        port: 7000,
        txt: {},
        ttl: 120,
        address: "127.0.0.1",
        address6: "fe80::1",
        fault: nil,
        drop: nil,
        conflicting_txt: nil
      }.freeze

      attr_reader :received, :port

      def initialize(port: 55_353, interfaces: ["lo0"], families: [:ipv4])
        @port = port
        @interfaces = interfaces
        @families = families
        @instances = []
        @received = []
        @answers = Hash.new(0)
        @random = Random.new(1234)
        @sockets = []
        @task = nil
      end

      def start
        @sockets = Discovery::Transport.open(port: @port, interfaces: @interfaces, families: @families)
        @task = Async::Task.current.async { receive_loop }
        self
      end

      def stop
        @task&.stop
        @sockets.each { |socket| socket.io.close rescue nil }
        @sockets = []
        @task = nil
        self
      end

      def advertise(**options)
        @instances << Instance.new(**DEFAULTS.merge(options))
        self
      end

      def unadvertise(name)
        instance = @instances.find { |candidate| candidate.name == name }
        return self unless instance

        @sockets.each { |socket| send_response(instance, socket, ttl: 0) }
        @instances.delete(instance)
        self
      end

      private

      def receive_loop
        loop do
          @sockets.each do |socket|
            packet = Discovery::Transport.receive(socket, 0.05)
            next unless packet

            data, source = packet
            message = Discovery::Codec.decode(data)
            next unless message.qr.zero?

            @received << Received.new(source: source, message: message, raw: data)
            handle(message, socket)
          end
        end
      rescue IOError, Errno::EBADF, Async::Stop
        nil
      end

      def handle(message, socket)
        message.questions.each do |question|
          next unless question.type == Resolv::DNS::Resource::IN::PTR

          type = normalize(question.name)
          @instances.each do |instance|
            next unless normalize(instance.type) == type
            next if instance.drop && @random.rand < instance.drop

            send_response(instance, socket)
          end
        end
      end

      def send_response(instance, socket, ttl: nil)
        ttl ||= instance.ttl
        sleep(0.1) if instance.fault == :delay_srv

        payload = Discovery::Codec.response(resources_for(instance, ttl))
        Discovery::Transport.send(socket, payload, @port)
      end

      def resources_for(instance, ttl)
        fqdn = "#{instance.name}.#{instance.type.chomp(".")}."
        resources = [
          {
            name: Resolv::DNS::Name.create(instance.type),
            ttl: ttl,
            data: Resolv::DNS::Resource::IN::PTR.new(Resolv::DNS::Name.create(fqdn))
          }
        ]

        unless instance.fault == :withhold_srv
          resources << {
            name: Resolv::DNS::Name.create(fqdn),
            ttl: ttl,
            data: Resolv::DNS::Resource::IN::SRV.new(
              0, 0, instance.port, Resolv::DNS::Name.create(instance.target)
            )
          }
        end

        txt = txt_for(instance)
        unless txt.empty?
          resources << {
            name: Resolv::DNS::Name.create(fqdn),
            ttl: ttl,
            data: Resolv::DNS::Resource::IN::TXT.new(*Discovery::Codec.encode_txt(txt))
          }
        end

        unless instance.fault == :ipv6_only
          resources << {
            name: Resolv::DNS::Name.create(instance.target),
            ttl: ttl,
            data: Resolv::DNS::Resource::IN::A.new(instance.address)
          }
        end

        if instance.address6
          resources << {
            name: Resolv::DNS::Name.create(instance.target),
            ttl: ttl,
            data: Resolv::DNS::Resource::IN::AAAA.new(instance.address6)
          }
        end

        resources
      end

      def txt_for(instance)
        @answers[instance.name] += 1
        if @answers[instance.name] > 1 && instance.conflicting_txt
          instance.conflicting_txt
        else
          instance.txt
        end
      end

      def normalize(value)
        value.to_s.chomp(".")
      end
    end
  end
end
