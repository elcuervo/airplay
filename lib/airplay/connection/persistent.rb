require "socket"
require "thread"
require "securerandom"
require "http/parser"

require "airplay/connection/parser"

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

      def initialize(address, options = {})
        @logger = Airplay::Logger.new("airplay::connection::persistent")
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
        puts "#{Time.now} Pushed to write queue: #{@write.size}"
        @write << req

        read
      end

      def read
        timeout(10) do
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
#        @_parser ||= Airplay::Connection::Parser.new
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
          puts "Pushed to read queue"
          puts @buffer
          parser.reset!
          #close
        end

        loop do
          break if @stop_loop

          puts("#{"%10.6f" % Time.now.to_f} Waiting for new request")
          packet = Packet.to_s(@write.pop)
          puts(packet)
          socket << packet

          puts("#{"%10.6f" % Time.now.to_f} Waiting for new response")
          puts(alive?)
          while chunk = socket.gets
            parser << chunk
          end
        end
      end
    end
  end
end
