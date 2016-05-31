require "airplay"
require "airplay/playable"
require "airplay/viewable"
require "airplay/device/features"
require "airplay/device/info"

module Airplay
  # Public: Represents an Airplay Node
  #
  class Device
    MissingAttributes = Class.new(KeyError)

    attr_reader :name, :address, :type, :password

    include Playable
    include Viewable

    def initialize(attributes = {})
      validate_attributes(attributes)

      @name     = attributes[:name]
      @address  = attributes[:address]
      @type     = attributes[:type]
      @password = attributes[:password]

      @it_has_password = false

      Airplay.configuration.load
    end

    # Public: Access the ip of the device
    #
    # Returns the memoized ip address
    #
    def ip
      @_ip ||= address.split(":").first
    end

    # Public: Sets server information based on text records
    #
    # Returns text records hash.
    #
    def text_records=(record)
      @text_records = {
        "model"      => record["model"],
        "features"   => record["features"],
        "macAddress" => record["deviceid"],
        "srcvers"    => record["srcvers"]
      }
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
      return @it_has_password if @it_has_password
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

    # Public: The unique id of the device (mac address)
    #
    # Returns the mac address based on basic_info or server_info
    #
    def id
      @_id ||= begin
        basic_info.fetch("macAddress", server_info["macAddress"])
      end
    end

    private

    def it_has_password!
      @it_has_password = true
    end

    # Private: Access the basic info of the device
    #
    # Returns a hash with the basic information
    #
    def basic_info
      @_basic_info ||= begin
        return @text_records if @text_records

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
      @_extra_info ||=
        begin
          new_device = clone
          new_device.refresh_connection
          new_device.address = "#{ip}:7100"

          result = new_device.connection.get("/stream.xml")
          raise result if !result.is_a?(Airplay::Connection::Response)

          response = result.response
          return {} if response.code != "200"

          plist = CFPropertyList::List.new(data: response.body)
          CFPropertyList.native_types(plist.value)
        rescue Airplay::Connection::PasswordRequired
          it_has_password!

          return {}
        end
    end

    # Private: Validates the mandatory attributes for a device
    #
    # attributes - The attributes hash to be validated
    #
    # Returns nothing or raises a MissingAttributes if some key is missing
    #
    def validate_attributes(attributes)
      if !([:name, :address] - attributes.keys).empty?
        raise MissingAttributes.new("A :name and an :address are mandatory")
      end
    end
  end
end
