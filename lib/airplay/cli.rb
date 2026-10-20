require "optparse"
require "uri"

require "airplay"
require "airplay/cli/version"

module Airplay
  # Public: Terminal entry point.
  module CLI
    ACTIONS = %w[help version list doctor play pause resume stop seek next previous rate view].freeze

    class << self
      def run(argv)
        options = {}
        parser = option_parser(options)

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
        when "pause" then transport(options, &:pause)
        when "resume" then transport(options, &:resume)
        when "stop" then transport(options, &:stop)
        when "next" then transport(options, &:next)
        when "previous" then transport(options, &:previous)
        when "seek" then seek(arguments.first, options)
        when "rate" then rate(arguments.first, options)
        when "view" then view(arguments.first, options)
        else
          warn "unknown action: #{action}"
          help
          false
        end
      rescue Airplay::Error => error
        error.emit!
        warn "#{error.code}: #{error.message}"
        false
      rescue OptionParser::ParseError => error
        warn error.message
        false
      end

      # Internal: The one option surface; help is rendered from it as well.
      def option_parser(options = {})
        OptionParser.new do |opts|
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
          opts.on("--no-now-playing", "Do not push now-playing to the receiver") do
            options[:now_playing] = false
          end
          opts.on("--position SECONDS", Float, "Start position for play") do |value|
            options[:position] = value
          end
          opts.on("--interactive", "View photos driven by arrow keys") { options[:interactive] = true }
          opts.on("--help", "Show this help") { options[:help] = true }
          opts.on("--version", "Show the CLI version") { options[:version] = true }
        end
      end

      def help
        puts option_parser
        puts <<~TEXT

          Actions:
            help     - This help.
            version  - The current airplay-cli version.
            list     - Lists the discovered devices and their server information.
            doctor   - Shows discovery and capability details.
            play     - Plays a URL or a local file.
            pause    - Pauses the current playback.
            resume   - Resumes the current playback.
            stop     - Stops the current playback.
            seek     - Seeks to a position in seconds.
            next     - Selects the next item.
            previous - Selects the previous item.
            rate     - Sets the playback rate.
            view     - Displays a picture or a folder slideshow.
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

        with_player(options) do |player|
          report_route(player.decision)
          player.play(source, position: options[:position] || 0.0)
          wait_with_progress(player) if options[:wait]
        end
        true
      end

      def transport(options)
        with_player(options) do |player|
          report_route(player.decision)
          yield player
        end
        true
      end

      def seek(position, options)
        return usage_failure("seek needs a position in seconds") unless position

        transport(options) { |player| player.seek(Float(position)) }
      end

      def rate(value, options)
        return usage_failure("rate needs a value") unless value

        transport(options) { |player| player.rate(Float(value)) }
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

      # Public: Drives the progress display from state changes, never from polling.
      def wait_with_progress(player)
        bar = nil
        last = 0.0
        player.wait do |state|
          Airplay::Status.emit("playback.state", status: state.status,
                                                 position: state.position,
                                                 duration: state.duration)
          next unless state.duration.to_f.positive?

          bar ||= Airplay::Status.progress("playback", state.duration)
          step = state.position.to_f - last
          bar&.increment(step) if step.positive?
          last = state.position.to_f
        end
      end

      def report_route(decision)
        return unless decision

        puts "route: #{decision.route} (#{decision.reason})"
        puts "firmware: #{decision.firmware || 'unknown'} " \
             "profile: #{decision.profile&.id || 'none'}"
      end

      def with_player(options)
        Airplay.sync do
          options[:record] = options[:url] ? nil : selected_record(options)
          device = target_device(options)
          capabilities = options[:record]&.capabilities
          Airplay::Player.open(device, capabilities: capabilities,
                                       force_legacy: options[:legacy],
                                       now_playing: options[:now_playing],
                                       password: options[:password],
                                       base_url: options[:url]) do |player|
            yield player
          end
        end
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
