require "uri"
require "forwardable"
require "micromachine"

module Airplay::Protocol
  # Public: The class that handles all the video playback
  #
  class Player
    extend Forwardable
    include Celluloid

    def_delegators :@machine, :state, :on

    def initialize
      start_the_machine
    end

    # Public: Plays a given url or file.
    #         Creates a new persistent connection to ensure that
    #         the socket will be kept alive
    #
    #   file_or_url - The url or file to be reproduced
    #   options - Optional starting time
    #
    def play(file_or_url, options = {})
      media_url = case true
                  when File.exists?(file_or_url)
                  when !!(file_or_url =~ URI::regexp)
                    file_or_url
                  else
                    raise Errno::ENOENT, file_or_url
                  end

      content = {
        "Content-Location" => media_url,
        "Start-Position" => options.fetch(:time, 0.0)
      }

      plist = CFPropertyList::List.new
      plist.value = CFPropertyList.guess(content)
      data = plist.to_str

      connection = Airplay::Connection.new
      response = connection.post("/play", data, {
        "Content-Type" => "application/x-apple-binary-plist"
      })

      connection.start_reverse_connection
      add_events_callback(connection)
      keep_alive(response.connection)

      resume
    end

    # Public: Handles the progress of the playback, the given &block get's
    #         executed every second while the video is played.
    #
    #   &block - Block to be executed in every playable second.
    #
    def progress(&block)
      every(1) do
        unless played? || stopped?
          progress_meter = info
          if progress_meter.any?
            block.call(progress_meter)
          else
            @machine.trigger(:stopped)
          end
        end
      end
    end

    # Public: Shows the current playback time if a video is being played.
    #
    # Returns a hash with the :duration and current :position
    #
    def scrub
      return unless playing?
      response = Airplay.connection.get("/scrub")
      parts = response.body.split("\n")
      Hash[parts.collect { |v| v.split(": ") }]
    end

    # Public: checks current playback information
    #
    # Returns a hash with the playback information
    #
    def info
      response = Airplay.connection.get("/playback-info").response
      plist = CFPropertyList::List.new(data: response.body)
      CFPropertyList.native_types(plist.value)
    end

    # Public: Resumes a paused video
    #
    def resume
      Airplay.connection.async.post("/rate?value=1")
    end

    # Public: Pauses a playing video
    #
    def pause
      Airplay.connection.async.post("/rate?value=0")
    end

    # Public: Stops the video
    #
    def stop
      Airplay.stop
    end

    def playing?; state == :playing end
    def paused?;  state == :paused  end
    def played?;  state == :played  end
    def stopped?; state == :stopped end

    # Public: Locks the execution until the video gets fully played
    #
    def wait
      sleep 0.1 while !played?
      stop
    end

    private

    # Private: Get ready the state machine
    #
    def start_the_machine
      @machine = MicroMachine.new(:stopped)

      @machine.when(:loading, :stopped => :loading)
      @machine.when(:playing, {
        :paused  => :playing,
        :loading => :playing,
        :stopped => :playing
      })

      @machine.when(:paused,  :loading => :paused,  :playing => :paused)
      @machine.when(:stopped, :playing => :played,  :paused  => :played)

      @machine.on(:played) { stop }
    end

    # Private: Keeps alive a persistent connection fetching the
    #          /scrub resource while the video is not stopped
    #
    def keep_alive(persistent)
      request = Net::HTTP::Get.new("/scrub")

      # TODO: This part must be refactored
      if Airplay.active.password?
        authentication = Airplay::Connection::Authentication.new(persistent)
        request = authentication.sign(request)
      end

      while !played? || !stopped? do
        persistent.request(request)
        sleep 1
      end
    end

    # Private: Adds the callback to the reverse connection callback pool
    #
    def add_events_callback(connection)
      connection.reverse.callbacks << proc do |event|
        if event["category"] == "video" && event.has_key?("state")
          @machine.trigger(event["state"].to_sym)
        end
      end
    end

  end
end
