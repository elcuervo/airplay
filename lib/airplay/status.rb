require "console"

module Airplay
  # Public: Structured lifecycle and playback events with console rendering.
  module Status
    class << self
      attr_writer :logger

      def logger
        @logger ||= build_logger(Airplay.configuration.output, Airplay.configuration.log_level)
      end

      def configure(configuration)
        @logger = build_logger(configuration.output, configuration.log_level)
      end

      def reset!
        @logger = nil
      end

      def emit(subject, level: :info, **fields)
        logger.public_send(level, subject, **fields)
      end

      # Public: A progress bar for terminal output, nil for structured-only sinks.
      def progress(subject, total, **options)
        return unless terminal?
        Console::Progress.new(subject, total, logger: logger, **options)
      end

      def terminal?
        output = Airplay.configuration.output
        output.respond_to?(:tty?) && output.tty?
      end

      private

      def build_logger(io, level)
        Console::Logger.new(Console::Output::Default.new(io), level: level)
      end
    end
  end
end
