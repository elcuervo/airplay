require "dnssd"
require "timeout"

require "airplay/logger"
require "airplay/devices"

module Airplay
  # Public: Browser class to find Airplay-enabled devices in the network
  #
  class Browser
    NoDevicesFound = Class.new(StandardError)

    SEARCH = "_airplay._tcp."

    def initialize
      @logger = Airplay::Logger.new("airplay::browser")
    end

    # Public: Browses in the search of devices and adds them to the nodes
    #
    # Returns nothing or raises NoDevicesFound if there are no devices
    #
    def browse
      timeout(5) do
        DNSSD.browse!(SEARCH) do |node|
          resolve(node)
          break unless node.flags.more_coming?
        end
      end
    rescue Timeout::Error => e
      raise NoDevicesFound
    end

    # Public: Access to the node list
    #
    # Returns the Devices list object
    #
    def devices
      @_devices ||= Devices.new
    end

    private

    # Private: Resolves a node given a node and a resolver
    #
    # node - The given node
    # resolver - The DNSSD::Server that is resolving nodes
    #
    # Returns if there are more nodes coming
    #
    def node_resolver(node, resolved)
      address = get_device_address(resolved)
      add_device(node.name, address)
      resolved.flags.more_coming?
    end

    # Private: Resolves the node complete address
    #
    # resolved - The DNS Resolved object
    #
    # Returns a string with the address (host:ip)
    #
    def get_device_address(resolved)
      host = get_device_host(resolved.target)
      "#{host}:#{resolved.port}"
    end

    # Private: Resolves the node ip or hostname
    #
    # resolved - The DNS Resolved object
    #
    # Returns a string with the ip or the hostname
    #
    def get_device_host(target)
      info = Socket.getaddrinfo(target, nil, Socket::AF_INET)
      info[0][2]
    rescue SocketError
      target
    end

    # Private: Creates and adds a device to the pool
    #
    # name    - The device name
    # address - The device address
    #
    # Returns nothing
    #
    def add_device(name, address)
      devices << Device.new(
        name:     name.gsub(/\u00a0/, ' '),
        address:  address
      )
    end

    # Private: Resolves the node information given a node
    #
    # node - The node from the DNSSD browsing
    #
    # Returns nothing
    #
    def resolve(node)
      resolver = DNSSD::Service.new
      resolver.resolve(node) do |resolved|
        break unless node_resolver(node, resolved)
      end
    end
  end
end
