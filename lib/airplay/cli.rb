require "optparse"

require "airplay"
require "airplay/cli/version"

module Airplay
  # Public: Terminal entry point. Protocol verbs land with the sibling changes.
  module CLI
    class << self
      def run(argv)
        options = {}
        parser = OptionParser.new do |opts|
          opts.banner = "Usage: air [OPTIONS] ACTION"
          opts.on("--help", "Show this help") { options[:help] = true }
          opts.on("--version", "Show the CLI version") { options[:version] = true }
        end

        action = parser.parse(argv).first
        return help if options[:help]
        return version if options[:version]

        case action || "help"
        when "help"
          help
        when "version"
          version
        else
          warn "unknown action: #{action}"
          help
          false
        end
      rescue OptionParser::ParseError => error
        warn error.message
        false
      end

      def help
        puts <<~TEXT
          Usage: air [OPTIONS] ACTION

          Actions:
            help    - This help.
            version - The current airplay-cli version.
        TEXT
        true
      end

      def version
        puts "air #{Airplay::CLI::VERSION}"
        true
      end
    end
  end
end
