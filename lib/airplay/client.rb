require "uuid"
require "celluloid"
require "net/http/persistent"
require "airplay/browser"
require "airplay/protocol"

module Airplay
  # Public: Handles all the outgoing interactions with the device
  #
  #   node - Optional node to connect
  #   browser - Optional browser class
  #
  class Client
    attr_reader :active, :slideshow, :app, :player

    def initialize(node = false, browser = Browser)
      Airplay.configuration.load

      @browser    = browser.new
      @app        = Airplay::Protocol::App
      @slideshow  = Airplay::Protocol::Slideshow.new
      @player     = Airplay::Protocol::Player.new

      @browser.browse
    end

    # Public: Sets the active node to be used
    #
    #   node_name - Node or string to be setted
    #
    def use(node_name)
      @active = if node_name.is_a?(Airplay::Node)
                  node_name
                else
                  nodes.find_by_name(node_name)
                end
    end

    # Public: Sends a given image to the device
    #
    #   media_or_io - The image
    #   options - Optional transitions.
    #
    def view(media_or_io, options = {})
      handler = Airplay::Protocol::Image.new(media_or_io, options)
      handler.broadcast
    end

    # Public: Plays a given video
    #
    #   file_or_url - The video to be played
    #   options - Optional start position
    #
    # Returns a Player object to control the playback
    #
    def play(file_or_url, options = {})
      @player.async.play(file_or_url, options)
    end

    # Public: Stops current playback
    #
    def stop
      Airplay.connection.post("/stop")
    end

    # Public: Lists found nodes
    #
    def nodes
      @browser.nodes
    end

    # Public: List the current active node
    #
    def active
      @active ||= @browser.nodes.first
    end
  end
end
