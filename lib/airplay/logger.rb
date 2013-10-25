require "log4r"

module Airplay
  # Public: A Log4r wrapper
  #
  class Logger < Log4r::Logger
    def initialize(*)
      super
      add Airplay.configuration.output
    end

    # Public: Helper method to be compatible with Net::HTTP
    #
    # message - The message to be logged as debug
    #
    # Returns nothing
    #
    def <<(message)
      debug message
    end
  end
end
