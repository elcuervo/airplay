require "rack"
require "socket"
require "uuid"

require "airplay/server/app"

module Airplay
  class Server
    include Celluloid

    def initialize
      @port = Airplay.configuration.port
      @server = Rack::Server.new(
        server: :webrick,
        Host: private_ip,
        Port: @port,
        app: App.app
      )

      start!
    end

    def serve(file)
      sleep 0.1 until running?
      asset_id = App.settings[:assets][file]

      "http://#{private_ip}:#{@port}/assets/#{asset_id}"
    end

    def start!
      Thread.start { @server.start }
    end

    private

    def running?
      begin
        socket = TCPSocket.new(private_ip, @port)
        socket.close unless socket.nil?
        true
      rescue Errno::ECONNREFUSED, Errno::EBADF, Errno::EADDRNOTAVAIL
        false
      end
    end

    def private_ip
      @_ip ||= Socket.ip_address_list.detect do |addr|
        addr.ipv4_private?
      end.ip_address
    end
  end
end
