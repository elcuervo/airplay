require "airplay/playable"
require "airplay/viewable"
require "airplay/device/features"
require "airplay/device/info"

module Airplay
  # Public: Represents an Airplay Node
  #
  class Device
    attr_reader :name, :address, :password

    include Playable
    include Viewable

    def initialize(attributes = {})
      @name = attributes[:name]
      @address = attributes[:address]
      @password = attributes[:password]

      Airplay.configuration.load
    end

    # Public: Access the ip of the device
    #
    # Returns the memoized ip address
    #
    def ip
      @_ip ||= address.split(":").first
    end

    # Public: Sets the password for the device
    #
    # passwd - The password string
    #
    # Returns nothing
    #
    def password=(passwd)
      @password = passwd
    end

    # Public: Checks if the devices has a password
    #
    # Returns boolean for the presence of a password
    #
    def password?
      !!password && !password.empty?
    end

    # Public: Set the addess of the device
    #
    # address - The address string of the device
    #
    # Returns nothing
    #
    def address=(address)
      @address = address
    end

    # Public: Access the Features of the device
    #
    # Returns the Featurs of the device
    #
    def features
      @_features ||= Features.new(self)
    end

    # Public: Access the Info of the device
    #
    # Returns the Info of the device
    #
    def info
      @_info ||= Info.new(self)
    end

    # Public: Access the full information of the device
    #
    # Returns a hash with all the information
    #
    def server_info
      @_server_info ||= basic_info.merge(extra_info)
    end

    # Public: Establishes a conection to the device
    #
    # Returns the Connection
    #
    def connection
      @_connection ||= Airplay::Connection.new(self)
    end

    # Public: Forces the refresh of the connection
    #
    # Returns nothing
    #
    def refresh_connection
      @_connection = nil
    end

    private

    # Private: Access the basic info of the device
    #
    # Returns a hash with the basic information
    #
    def basic_info
      @_basic_info ||= begin
        response = connection.get("/server-info").response
        plist = CFPropertyList::List.new(data: response.body)
        CFPropertyList.native_types(plist.value)
      end
    end

    # Private: Access extra info of the device
    #
    # Returns a hash with extra information
    #
    def extra_info
      @_extra_info ||= begin
        new_device = clone
        new_device.refresh_connection
        new_device.address = "#{ip}:7100"

        response = new_device.connection.get("/stream.xml").response
        plist = CFPropertyList::List.new(data: response.body)
        CFPropertyList.native_types(plist.value)
      end
    end
  end
end
