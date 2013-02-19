require "log4r"

module Airplay
  class Logger < Log4r::Logger
    def initialize(*)
      super
      add Airplay.configuration.output
    end

    def <<(message)
      debug message
    end
  end
end
