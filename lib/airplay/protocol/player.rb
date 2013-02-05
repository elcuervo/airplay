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

      @callback = proc do |event|
        @machine.trigger(event["state"].to_sym) if event["category"] == "video"
      end
    end

    # Public: Plays a given url or file
    #
    #   file_or_url - The url or file to be reproduced
    #   options - Optional starting time
    #
    def play(file_or_url, options = {})
      add_events_callback

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

      Airplay.connection.async.post("/play", plist.to_str, {
        "Content-Type" => "application/x-apple-binary-plist"
      })

      resume
    end

    # Public: Handles the progress of the playback, the given &block get's
    #         executed every second while the video is played.
    #
    #   &block - Block to be executed in every playable second.
    #
    def progress(&block)
      timer = after(1) do
        if played? || stopped?
          timer.cancel
        else
          progress_meter = scrub
          block.call(progress_meter) if progress_meter
          timer.reset
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

    # Private: Adds the callback to the reverse connection callback pool
    #
    def add_events_callback
      if !Airplay.connection.reverse.callbacks.include?(@callback)
        Airplay.connection.reverse.callbacks << @callback
      end
    end

  end
end
