require "forwardable"

module Airplay
  class Group
    include Enumerable
    extend  Forwardable

    def_delegators :@devices, :each, :size, :empty?

    def initialize(name)
      @devices = []
      @name = name
    end

    def <<(device)
      @devices << device
    end

    def play(file_or_url, options = {})
      @devices.map { |device| device.play(file_or_url, options) }
    end
  end
end
