require "socket"
require "thread"
require "securerandom"
require "http/parser"

require "airplay/loggable"

module Airplay
  # Public: The class that handles all the outgoing basic HTTP connections
  #
  class Connection
    # Public: Class that wraps a persistent connection to point to the airplay
    #         server and other configuration
    #
    class Persistent
      module Packet
        CRLF = "\r\n".freeze

        def self.to_s(req)
          packet = "#{req.method} #{req.path} HTTP/1.1#{CRLF}"

          req["Content-Length"] ||= req.body ? req.body.size : 0

          req.each_header do |header, value|
            header_parts = header.split("-").map(&:capitalize)
            packet += "#{header_parts.join("-")}: #{value}#{CRLF}"
          end

          packet += CRLF
          packet += req.body if req.body

          packet
        end
      end

      attr_reader :session, :mac_address

      include Loggable

      def initialize(address, options = {})
        @ip, @port = address.split(":")

        @session = SecureRandom.uuid
        @mac_address = "0x#{SecureRandom.hex(6)}"
        @stop_loop = false

        @thread = Thread.new { event_loop }
        @write = Queue.new
        @read = Queue.new
      end

      def close
        socket.close
        @stop_loop = true
      end

      # Public: send a request to the active server
      #
      #   request - The Net::HTTP request to be executed
      #   &block  - An optional block to be executed within the block
      #
      def request(req)
        log.debug("Pushed to write queue: #{@write.size}")
        @write << req

        read
      end

      def read
        Timeout.timeout(10) do
          while @read.empty?
            sleep 0.1
          end
          @read.pop
        end
      end

      def alive?
        !socket.closed?
      end

      def socket
        @_socket ||= TCPSocket.open(@ip, @port)
      end

      def parser
        @_parser ||= Http::Parser.new
      end

      def working?
        !@write.empty?
      end

      def can_read?
        !@read.empty?
      end

      def event_loop
        parser.on_message_begin = proc { @buffer = '' }
        parser.on_body = proc { |chunk| @buffer << chunk }

        parser.on_message_complete = proc do |env|
          @read << Response.new(parser, @buffer)

          log.debug("Pushed to read queue")
          parser.reset!
        end

        loop do
          break if @stop_loop

          log.debug("Waiting for new request")

          packet = Packet.to_s(@write.pop)
          socket << packet

          log.debug("Waiting for new response")

          while chunk = socket.gets
            parser << chunk
          end
        end
      end
    end
  end
end
