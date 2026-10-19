require "async"
require "async/http"
require "console"

require "airplay/version"
require "airplay/errors"
require "airplay/configuration"
require "airplay/clock"
require "airplay/status"
require "airplay/resolver"
require "airplay/device"
require "airplay/session"
require "airplay/discovery"

# Public: AirPlay sender for Ruby 4.
module Airplay
  class << self
    def configuration
      @configuration ||= Configuration.new
    end

    # Public: Applies a configuration block and rebuilds the status logger.
    def configure
      yield configuration if block_given?
      Status.configure(configuration)
      configuration
    end

    # Public: Restores defaults; used between tests.
    def reset_configuration!
      @configuration = Configuration.new
      @clock = nil
      @resolver = nil
      @devices = nil
      Status.reset!
      configuration
    end

    def clock
      @clock ||= Clock.new
    end

    attr_writer :clock

    def resolver
      @resolver ||= Resolver.new
    end

    attr_writer :resolver

    # Public: Runs the block inside the process reactor and returns its value.
    # Nested calls join the running reactor instead of starting another one.
    def sync(&block)
      raise ArgumentError, "block required" unless block

      Sync { |task| block.call(task) }
    end

    # Public: Synchronous facade for one-shot work on a session.
    def open(device, **options, &block)
      sync { |task| Session.open(device, task: task, **options, &block) }
    end

    # Public: Current discovery records; browses when the cache is cold.
    def devices
      @devices ||= Discovery::Devices.new
    end

    def browse(**options)
      devices.browse(**options)
    end

    def [](name)
      devices[name]
    end
  end
end
