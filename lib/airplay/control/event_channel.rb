require "io/stream"
require "socket"

require "airplay/plist"
require "airplay/pairing/frame"

module Airplay
  module Control
    # Public: Listener for the receiver's reverse event connection.
    class EventChannel
      ACK = "HTTP/1.1 200 OK\r\ncontent-length: 0\r\n\r\n".b

      attr_reader :port, :events, :acks

      def initialize(key, on_event: nil)
        @key = key.to_s
        @on_event = on_event
        @events = []
        @acks = 0
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
        writer = Airplay::Pairing::Frame.new(@key)
        buffer = +"".b
        loop do
          header = stream.read_exactly(2)
          length = header.unpack1("v")
          return if length > Airplay::Pairing::Frame::MAX_LENGTH

          plaintext = reader.decrypt(header + stream.read_exactly(length + Airplay::Pairing::Frame::TAG_LENGTH))
          if buffer.empty? && !http_request?(plaintext)
            raw(plaintext)
            next
          end

          buffer << plaintext
          while (message = take_message(buffer))
            handle(stream, writer, message[0])
            buffer = message[1]
          end
        end
      rescue EOFError, SystemCallError, IOError
        nil
      ensure
        @lost = true
        stream&.close
      end

      def http_request?(plaintext)
        plaintext.match?(%r{\A[A-Z]+ \S+ HTTP/1\.[01]\r\n})
      end

      # Internal: Splits complete HTTP messages from the accumulated frames.
      def take_message(buffer)
        head_end = buffer.index("\r\n\r\n")
        return nil unless head_end

        length = content_length(buffer.byteslice(0, head_end))
        return nil if buffer.bytesize < head_end + 4 + length

        body = buffer.byteslice(head_end + 4, length)
        [body, buffer.byteslice(head_end + 4 + length..)]
      end

      # Internal: A legacy harness script pushes one raw plist per frame, unacknowledged.
      def raw(plaintext)
        event = decode(plaintext)
        return nil unless event

        @events << event
        @on_event&.call(event)
      end

      def content_length(head)
        head.split("\r\n").drop(1).each do |line|
          name, value = line.split(":", 2)
          return value.to_s.strip.to_i if name.to_s.strip.downcase == "content-length"
        end
        0
      end

      def handle(stream, writer, body)
        event = decode(body)
        @acks += 1
        stream.write(writer.encrypt(ACK), flush: true)
        return nil unless event

        @events << event
        @on_event&.call(event)
      rescue Airplay::Error
        nil
      end

      def decode(body)
        Airplay::Plist.load(body.to_s) if body.to_s.start_with?("bplist00")
      rescue Airplay::Error
        nil
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
