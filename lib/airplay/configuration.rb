require 'log4r/config'

module Airplay
  class Configuration
    attr_accessor :log_level, :output

    def initialize
      Log4r.define_levels(*Log4r::Log4rConfig::LogLevels)

      @log_level = Log4r::WARN
      @output = Log4r::Outputter.stdout
    end

    def load
      Log4r::Logger.root.add @output
      Log4r::Logger.root.level = Log4r.const_get(@log_level.upcase)
    end
  end
end
