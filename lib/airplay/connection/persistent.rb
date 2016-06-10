require "socket"
require "thread"
require "securerandom"

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
      end

      def queue
        @_queue ||= Queue.new
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
      def request(request)
        queue << request
      end

      def alive?
        !socket.closed?
      end

      def socket
        @_socket ||= TCPSocket.new(@ip, @port)
      end

      def working?
        !queue.empty?
      end

      def event_loop
        loop do
          break if @stop_loop

          packet = Packet.to_s(queue.pop)
          socket << packet
        end
      end
    end
  end
end
