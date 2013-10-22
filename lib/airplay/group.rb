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

    def <<(device)
      @devices << device
    end

    def play(file_or_url, options = {})
      @players = @devices.map { |device| device.play(file_or_url, options) }
      Players.new(@players)
    end

    def view(media_or_io, options = {})
      @devices.map do |device|
        ok = device.view(media_or_io, options)
        [device, ok]
      end
    end
  end
end
