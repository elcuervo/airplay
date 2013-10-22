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
    #   device_name - The name of the device
    #
    # Returns a Node object
    #
    def find_by_name(device_name)
      find_by_block { |device| device if device.name == device_name }
    end

    def find_by_ip(ip)
      find_by_block { |device| device if device.ip == ip }
    end

    def add(name, address)
      self << Device.new(name: name, address: address)
    end

    # Public: Adds a device to the list
    #
    #   value - The Node
    def <<(device)
      return if find_by_ip(device.ip)
      @items << device
    end

    private

    def find_by_block(&block)
      @items.find(&block)
    end
  end
end
