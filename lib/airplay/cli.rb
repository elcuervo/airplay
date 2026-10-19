require "optparse"

require "airplay"
require "airplay/cli/version"

module Airplay
  # Public: Terminal entry point.
  module CLI
    class << self
      def run(argv)
        options = {}
        parser = OptionParser.new do |opts|
          opts.banner = "Usage: air [OPTIONS] ACTION"
          opts.on("--interface NAME", "Interface(s) to browse (comma separated)") do |value|
            options[:interfaces] = value.split(",")
          end
          opts.on("--window SECONDS", Float, "Browse window in seconds") do |value|
            options[:window] = value
          end
          opts.on("--help", "Show this help") { options[:help] = true }
          opts.on("--version", "Show the CLI version") { options[:version] = true }
        end

        action = parser.parse(argv).first
        configure(options)
        return help if options[:help]
        return version if options[:version]

        case action || "help"
        when "help"
          help
        when "version"
          version
        when "list"
          list
        when "doctor"
          doctor
        else
          warn "unknown action: #{action}"
          help
          false
        end
      rescue Airplay::Error => error
        warn "#{error.code}: #{error.message}"
        false
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
            list    - Lists the discovered devices.
            doctor  - Shows discovery and capability details.
        TEXT
        true
      end

      def version
        puts "air #{Airplay::CLI::VERSION}"
        true
      end

      def list
        Airplay.devices.each do |device|
          puts "#{device.display_name} (#{device.service_type}) #{device.host}:#{device.port}"
        end
        true
      end

      def doctor
        devices = Airplay.devices
        devices.browse

        if devices.none?
          puts "No devices found."
          return true
        end

        devices.each do |device|
          puts <<~TEXT
            Name: #{device.display_name}
            Type: #{device.service_type}
            Host: #{device.host}
            Port: #{device.port}
            Addresses: #{device.addresses.map(&:to_s).join(", ")}
            Capabilities: #{capability_summary(device.capabilities)}
            TXT: #{device.txt.inspect}
          TEXT
        end
        true
      end

      private

      def configure(options)
        Airplay.configure do |config|
          config.discovery_interfaces = options[:interfaces] if options[:interfaces]
          config.discovery_window = options[:window] if options[:window]
        end
      end

      def capability_summary(capabilities)
        names = %i[
          video video_v2 photo slideshow screen audio buffered_audio ptp
          unified_media_control pairing transient_pairing airplay2
        ]
        names.select { |name| capabilities.public_send("#{name}?") }.join(", ")
      end
    end
  end
end
