require "forwardable"
require "airplay/device"

module Airplay
  # Public: Represents an array of devices
  #
  class Devices
    include Enumerable
    extend  Forwardable

    def_delegators :@items, :each, :size, :empty?

    def initialize
      @items = []
    end

    # Public: Finds a device given a name
    #
    # device_name - The name of the device
    #
    # Returns a Device object
    #
    def find_by_name(device_name)
      find_by_block { |device| device if device.name == device_name }
    end

    # Public: Finds a device given an ip
    #
    # ip - The ip of the device
    #
    # Returns a Device object
    #
    def find_by_ip(ip)
      find_by_block { |device| device if device.ip == ip }
    end

    # Public: Adds a device to the pool
    #
    # name    - The name of the device
    # address - The address of the device
    #
    # Returns nothing
    #
    def add(name, address)
      device = Device.new(name: name, address: address)
      self << device
      device
    end

    # Public: Adds a device to the list
    #
    # value - The Device
    #
    # Returns nothing
    #
    def <<(device)
      return if find_by_ip(device.ip)
      @items << device
    end

    private

    # Private: Finds a devices based on a block
    #
    # &block - The block to be executed
    #
    # Returns the result of the find on that given block
    #
    def find_by_block(&block)
      @items.find(&block)
    end
  end
end
