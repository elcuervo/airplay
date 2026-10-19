require "io/stream"
require "socket"

require "airplay/plist"
require "airplay/pairing/frame"

module Airplay
  module Control
    # Public: Listener for the receiver's reverse event connection.
    class EventChannel
      attr_reader :port, :events

      def initialize(key)
        @key = key.to_s
        @events = []
        @lost = false
        @server = TCPServer.new("127.0.0.1", 0)
        @port = @server.addr[1]
      end

      def start
        @task = Async::Task.current.async(transient: true) { receive }
        self
      end

      def lost?
        @lost
      end

      def close
        @lost = true
        @task&.stop
        @server.close
      end

      private

      def receive
        client = accept_client
        return unless client

        stream = IO::Stream(client)
        reader = Airplay::Pairing::Frame.new(@key)
        loop do
          header = stream.read_exactly(2)
          length = header.unpack1("v")
          return if length > Airplay::Pairing::Frame::MAX_LENGTH

          @events << Airplay::Plist.load(
            reader.decrypt(header + stream.read_exactly(length + Airplay::Pairing::Frame::TAG_LENGTH))
          )
        end
      rescue EOFError, SystemCallError, IOError
        nil
      ensure
        @lost = true
        stream&.close
      end

      def accept_client
        loop do
          client, = @server.accept_nonblock(exception: false)
          return client if client.is_a?(TCPSocket)

          sleep(0.01)
        end
      end
    end
  end
end
