require "rack"
require "socket"
require "puma"

require "airplay/loggable"
require "airplay/server/app"

module Airplay
  class Server
    attr_reader :port

    include Loggable

    def initialize
      @port = Airplay.configuration.port || find_free_port
      @server = Rack::Server.new(
        Host: private_ip,
        Port: @port,
        AccessLog: [],
        Silent: true,
        server: :puma,
        app: App.app
      )

      start!
    end

    # Public: Adds a file to serve
    #
    # file - The file path to be served
    #
    # Returns the url that the file will have
    #
    def serve(file)
      sleep 0.1 until running?

      filename = File.basename(file)
      asset_id = App.settings[:assets][file]

      log.debug("asset_id: #{asset_id}, file: #{filename}")

      "http://#{private_ip}:#{@port}/assets/#{asset_id}/#{filename}"
    end

    # Public: Starts the server in a new thread
    #
    # Returns nothing
    #
    def start!
      Thread.start { @server.start }
    end

    private

    # Private: Checks the state if the server by attempting a connection to it
    #
    # Returns a boolean with the state
    #
    def running?(port = @port)
      begin
        socket = TCPSocket.new(private_ip, port)
        socket.close unless socket.nil?
        true
      rescue Errno::ECONNREFUSED, Errno::EBADF, Errno::EADDRNOTAVAIL
        false
      end
    end

    # Private: The local ip of the machine
    #
    # Returns the ip address of the current machine
    #
    def private_ip
      @_ip ||= Socket.ip_address_list.detect do |addr|
        addr.ipv4_private?
      end.ip_address
    end

    # Private: Finds a free port by asking the kernel for a free one
    #
    # Returns a free port number
    #
    def find_free_port
      socket = Socket.new(Socket::AF_INET, Socket::SOCK_STREAM, 0)
      socket.listen(1)
      port = socket.local_address.ip_port
      socket.close
      port
    end
  end
end
