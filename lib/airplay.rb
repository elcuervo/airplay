require "airplay/configuration"
require "airplay/browser"
require "airplay/group"
require "airplay/server"
require "airplay/version"

# Public: Airplay core module
#
module Airplay
  # Airplay will throw exceptions with these types
  class Error < StandardError; end
  class Error::UnsupportedType < Error; end

  class << self
    # Public: General configuration
    #
    # &block - The block that will modify the configuration
    #
    # Returns the configuration file.
    #
    def configure(&block)
      yield(configuration) if block
    end

    # Public: Access the server object
    #
    # Returns the Server object
    #
    def server
      @_server ||= Server.new
    end

    # Public: Browses for devices in the current network
    #
    # Returns nothing.
    #
    def browse
      browser.browse
    end

    # Public: Access or create a group based on a key
    #
    # Returns the Hash object.
    #
    def group
      @_group ||= Hash.new { |h, k| h[k] = Group.new(k) }
    end

    # Public: Helper method to access all the devices
    #
    # Returns a Group with all the devices.
    #
    def all
      @_all ||= begin
        group = Group.new(:all)
        devices.each { |device| group << device }
        group
      end
    end

    # Public: Lists found devices if autodiscover is enabled
    #
    # Returns an Array with all the devices
    #
    def devices
      browse if browser.devices.empty? && configuration.autodiscover
      browser.devices
    end

    # Public: Access the configuration object
    #
    # Returns the Configuration object
    #
    def configuration
      @_configuration ||= Configuration.new
    end

    # Public: Access a device by name
    #
    # device_name - The name to search on the devices
    #
    # Returns the found device
    #
    def [](device_name)
      devices.find_by_name(device_name)
    end

    private

    # Private: Access the browser object
    #
    # Returns the momoized Browser object
    #
    def browser
      @_browser ||= Browser.new
    end
  end
end
