require "airplay/configuration"
require "airplay/browser"
require "airplay/group"
require "airplay/version"

# Public: Airplay core module
#
module Airplay
  class << self
    def configure(&block)
      yield(configuration) if block
    end

    def browse
      browser.browse
    end

    def group
      @_group ||= Hash.new { |h, k| h[k] = Group.new(k) }
    end

    def all
      @_all ||= begin
        group = Group.new(:all)
        devices.each { |device| group << device }
        group
      end
    end

    # Public: Lists found devices
    #
    def devices
      browse if browser.devices.empty?
      browser.devices
    end

    def configuration
      @_configuration ||= Configuration.new
    end

    def [](device_name)
      devices.find_by_name(device_name)
    end

    private

    def browser
      @_browser ||= Browser.new
    end
  end
end
