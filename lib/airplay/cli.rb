require "optparse"
require "uri"

require "airplay"
require "airplay/cli/version"

module Airplay
  # Public: Terminal entry point.
  module CLI
    ACTIONS = %w[help version list doctor play view].freeze

    class << self
      def run(argv)
        options = {}
        parser = OptionParser.new do |opts|
          opts.banner = "Usage: air [OPTIONS] ACTION [SOURCE]"
          opts.on("--interface NAME", "Interface(s) to browse (comma separated)") do |value|
            options[:interfaces] = value.split(",")
          end
          opts.on("--window SECONDS", Float, "Browse window in seconds") do |value|
            options[:window] = value
          end
          opts.on("--device NAME", "Discovered device to target") { |value| options[:device] = value }
          opts.on("--password PASSWORD", "Receiver password") { |value| options[:password] = value }
          opts.on("--url URL", "Target a receiver directly, skipping discovery") do |value|
            options[:url] = value
          end
          opts.on("--transition NAME", "Photo transition (None, Dissolve, SlideLeft, SlideRight)") do |value|
            options[:transition] = value
          end
          opts.on("--wait [SECONDS]", Float, "Wait for playback, or slideshow interval") do |value|
            options[:wait] = value || true
          end
          opts.on("--legacy", "Force the legacy AirPlay 1 route") { options[:legacy] = true }
          opts.on("--interactive", "View photos driven by arrow keys") { options[:interactive] = true }
          opts.on("--help", "Show this help") { options[:help] = true }
          opts.on("--version", "Show the CLI version") { options[:version] = true }
        end

        action, *arguments = parser.parse(argv)
        configure(options)
        return help if options[:help]
        return version if options[:version]

        case action || "help"
        when "help" then help
        when "version" then version
        when "list" then list
        when "doctor" then doctor
        when "play" then play(arguments.first, options)
        when "view" then view(arguments.first, options)
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
          Usage: air [OPTIONS] ACTION [SOURCE]

          Actions:
            help    - This help.
            version - The current airplay-cli version.
            list    - Lists the discovered devices and their server information.
            doctor  - Shows discovery and capability details.
            play    - Plays a URL or a local file.
            view    - Displays a picture or a folder slideshow.

          Options:
            --url URL          Target a receiver directly, skipping discovery.
            --device NAME      Target a discovered device.
            --password PASS    Receiver password.
            --transition NAME  Photo transition: None, Dissolve, SlideLeft or SlideRight.
            --wait [SECONDS]   Wait for playback, or the slideshow interval.
            --legacy           Force the legacy AirPlay 1 route.
        TEXT
        true
      end

      def version
        puts "air #{Airplay::CLI::VERSION}"
        true
      end

      # Public: Maps an arrow key sequence to a documented transition.
      def transition_for(key)
        { "\e[C" => "SlideLeft", "\e[D" => "SlideRight", " " => "None" }[key]
      end

      def list
        Airplay.devices.each do |record|
          info = device_information(record).to_h
          fields = [
            record.display_name,
            "#{record.host}:#{record.port}",
            info["deviceid"],
            info["model"],
            info["srcvers"],
            resolution(info),
            ("password" if record.capabilities.password_required?)
          ].compact
          puts fields.join(" ")
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
        Airplay.configuration.digest_username = nil
      end

      def play(source, options)
        return usage_failure("play needs a URL or a file") unless source

        with_session(options) do |session|
          session.play(source)
          session.wait if options[:wait]
        end
        true
      end

      def view(source, options)
        return usage_failure("view needs a picture or a folder") unless source

        interval = options[:wait].is_a?(Float) ? options[:wait] : 5.0
        transition = options[:transition] || "None"

        with_session(options) do |session|
          if File.directory?(source)
            Dir.children(source).sort.each do |entry|
              session.photo(File.join(source, entry), transition: transition)
              Airplay.clock.sleep(interval)
            end
          else
            session.photo(source, transition: transition)
          end

          while options[:interactive] && (key = read_key)
            break if key == "q"

            name = transition_for(key)
            session.photo(source, transition: name) if name
          end
        end
        true
      end

      def read_key
        key = $stdin.getc
        return nil if key.nil?

        key += $stdin.getc.to_s + $stdin.getc.to_s if key == "\e"
        key
      end

      def with_session(options)
        Airplay.sync do
          options[:record] = options[:url] ? nil : selected_record(options)
          device = target_device(options)
          capabilities = options[:record]&.capabilities
          Airplay::Session.open(device, base_url: options[:url], password: options[:password],
                                        legacy: options[:legacy], capabilities: capabilities) do |session|
            yield session
          end
        end
      end

      def selected_record(options)
        options[:device] ? Airplay.devices[options[:device]] : Airplay.devices.first
      end

      def target_device(options)
        return device_for_url(options[:url]) if options[:url]

        record = options[:record]
        unless record
          raise Airplay::ConfigurationError.new("no device selected", code: :no_device)
        end

        Airplay::Device.new(name: record.display_name, host: record.host, port: record.port)
      end

      def device_for_url(url)
        uri = URI.parse(url)
        Airplay::Device.new(name: uri.host, host: uri.host, port: uri.port || 7000)
      end

      def device_information(record)
        Airplay.sync do
          device = Airplay::Device.new(name: record.display_name, host: record.host, port: record.port)
          Airplay::Session.open(device) { |session| session.server_info }
        end
      rescue Airplay::Error
        {}
      end

      def resolution(info)
        return nil unless info["width"] && info["height"]

        "#{info["width"]}x#{info["height"]}"
      end

      def usage_failure(message)
        warn message
        false
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
