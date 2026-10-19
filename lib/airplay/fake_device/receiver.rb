require "async"
require "async/http"
require "json"
require "socket"

require "airplay"

module Airplay
  module FakeDevice
    # Public: In-process AirPlay receiver double used by the protocol lane.
    class Receiver
      Exchange = Struct.new(:method, :path, :headers, :body, keyword_init: true)
      Record = Struct.new(:name, :model, :features, :password, keyword_init: true)

      DEFAULT_RECORD = {
        name: "Fake Apple TV",
        model: "AppleTV6,2",
        features: 0,
        password: nil
      }.freeze

      attr_reader :record, :exchanges, :faults, :port
      attr_accessor :connections

      def initialize(record: {}, faults: {})
        @record = Record.new(**DEFAULT_RECORD.merge(record))
        @faults = faults.dup
        @exchanges = []
        @connections = 0
        @bound = nil
        @server = nil
        @task = nil
      end

      def start
        endpoint = Async::HTTP::Endpoint.parse("http://127.0.0.1:0")
        @bound = endpoint.bound
        @port = @bound.sockets.first.to_io.local_address.ip_port
        http_endpoint = Async::HTTP::Endpoint.parse(url, @bound)
        @server = Server.new(method(:handle), http_endpoint, receiver: self)
        @task = Async::Task.current.async { @server.run }
        self
      end

      def stop
        @task&.stop
        @bound&.close
        @task = nil
        @server = nil
        self
      end

      def url
        "http://127.0.0.1:#{port}"
      end

      def device(**options)
        Airplay::Device.new(name: record.name, host: "127.0.0.1", port: port,
                            model: record.model, **options)
      end

      def handle(request)
        index = @exchanges.size + 1
        @exchanges << Exchange.new(
          method: request.method,
          path: request.path,
          headers: request.headers.to_h.transform_values do |value|
            value.is_a?(Array) && value.length == 1 ? value.first : value
          end,
          body: request.body&.join
        )

        fault = @faults[index] || {}
        case fault[:kind]
        when :delay
          sleep(fault.fetch(:seconds, 1))
          respond(200, record_json)
        when :status
          respond(fault.fetch(:status, 500), "error")
        when :auth
          respond(401, "", { "www-authenticate" => %(Digest realm="raop", nonce="fake") })
        when :truncate
          body = record_json
          respond(200, body[0, body.length / 2],
                  { "content-length" => body.bytesize.to_s })
        when :corrupt
          body = record_json
          respond(200, body.sub(/\A\{/, "["))
        else
          respond(200, record_json)
        end
      end

      def connection_fault
        @faults[:connection]
      end

      private

      def record_json
        JSON.generate(
          name: record.name,
          model: record.model,
          features: record.features,
          password: !record.password.nil?
        )
      end

      def respond(status, body, headers = {})
        Protocol::HTTP::Response[
          status,
          { "content-type" => "application/json" }.merge(headers),
          [body]
        ]
      end

      # Public: Applies connection-level faults before the HTTP protocol runs.
      class Server < Async::HTTP::Server
        def initialize(app, endpoint, receiver:)
          super(app, endpoint)
          @receiver = receiver
        end

        def accept(peer, address, task: Async::Task.current)
          @receiver.connections += 1

          case @receiver.connection_fault
          when :drop
            peer.close
            nil
          when :reset
            io = peer.respond_to?(:to_io) ? peer.to_io : peer
            io.setsockopt(Socket::SOL_SOCKET, Socket::SO_LINGER, [1, 0].pack("ii"))
            io.close
            nil
          else
            super
          end
        end
      end
    end
  end
end
