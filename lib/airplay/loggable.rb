require "logging"

module Airplay
  module Loggable
    def log
      @_log ||= Logging.logger[self]
    end
  end
end
