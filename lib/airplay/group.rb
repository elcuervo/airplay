require "forwardable"
require "airplay/group/players"

module Airplay
  class Group
    include Enumerable
    extend  Forwardable

    def_delegators :@devices, :each, :size, :empty?

    def initialize(name)
      @devices = []
      @players = []
      @name = name
    end

    # Public: Adds a device to the list
    #
    # value - The Device
    #
    # Returns nothing
    #
    def <<(device)
      @devices << device
    end

    # Public: Plays a video on all the grouped devices
    #
    # file_or_url - The file or url to be sent to the devices
    # options     - The options to be sent
    #
    # Returns a Players instance that syncs the devices
    #
    def play(file_or_url, options = {})
      @players = @devices.map { |device| device.play(file_or_url, options) }
      Players.new(@players)
    end

    # Public: Views an image on all the grouped devices
    #
    # media_or_io - The file or url to be sent to the devices
    # options     - The options to be sent
    #
    # Returns an array of arrays with the result of the playback
    #
    def view(media_or_io, options = {})
      @devices.map do |device|
        ok = device.view(media_or_io, options)
        [device, ok]
      end
    end
  end
end
