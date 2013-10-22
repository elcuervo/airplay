require "uri"
require "forwardable"
require "micromachine"
require "celluloid"
require "cfpropertylist"

require "airplay/connection"
require "airplay/protocol/timers"
require "airplay/protocol/playback_info"

module Airplay::Protocol
  # Public: The class that handles all the video playback
  #
  class Player
    extend Forwardable
    include Celluloid

    def_delegators :@machine, :state, :on

    attr_reader :device

    def initialize(device)
      @device = device
    end

    # Public: Plays a given url or file.
    #         Creates a new persistent connection to ensure that
    #         the socket will be kept alive
    #
    #   file_or_url - The url or file to be reproduced
    #   options - Optional starting time
    #
    def play(file_or_url, options = {})
      start_the_machine
      check_for_playback_status

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

      data = content.map { |k, v| "#{k}: #{v}" }.join("\r\n")

      response = persistent.async.post("/play", data + "\r\n", {
        "Content-Type" => "text/parameters"
      })

      timers.reset
    end

    # Public: Handles the progress of the playback, the given &block get's
    #         executed every second while the video is played.
    #
    #   &block - Block to be executed in every playable second.
    #
    def progress(callback)
      timers << every(1) do
        callback.call(info) if playing?
      end
    end

    # Public: Shows the current playback time if a video is being played.
    #
    # Returns a hash with the :duration and current :position
    #
    def scrub
      return unless playing?
      response = connection.get("/scrub")
      parts = response.body.split("\n")
      Hash[parts.collect { |v| v.split(": ") }]
    end

    # Public: checks current playback information
    #
    # Returns a hash with the playback information
    #
    def info
      response = connection.get("/playback-info").response
      plist = CFPropertyList::List.new(data: response.body)
      hash = CFPropertyList.native_types(plist.value)
      PlaybackInfo.new(hash)
    end

    # Public: Resumes a paused video
    #
    def resume
      connection.async.post("/rate?value=1")
    end

    # Public: Pauses a playing video
    #
    def pause
      connection.async.post("/rate?value=0")
    end

    # Public: Stops the video
    #
    def stop
      connection.post("/stop")
    end

    def playing?; state == :playing end
    def paused?;  state == :paused  end
    def played?;  state == :played  end
    def stopped?; state == :stopped end

    # Public: Locks the execution until the video gets fully played
    #
    def wait
      sleep 0.1 while !played? || stopped?
      cleanup
    end

    def cleanup
      timers.cancel
      persistent.close
    end

    private

    def timers
      @_timers ||= Timers.new
    end

    def connection
      @_connection ||= Airplay::Connection.new(@device)
    end

    def persistent
      @_persistent ||= Airplay::Connection.new(@device, keep_alive: true)
    end

    def check_for_playback_status
      timers << every(1) do
        case true
        when info.stopped? then @machine.trigger(:stopped) if playing?
        when info.played?  then @machine.trigger(:played)  if playing?
        when info.playing? then @machine.trigger(:playing) if !playing?
        when info.paused?  then @machine.trigger(:paused)  if playing?
        end
      end
    end

    # Private: Get ready the state machine
    #
    def start_the_machine
      @machine = MicroMachine.new(:stopped)

      @machine.on(:stopped) { cleanup }
      @machine.on(:played)  { cleanup }

      @machine.when(:loading, :stopped => :loading)
      @machine.when(:playing, {
        :paused  => :playing,
        :loading => :playing,
        :stopped => :playing
      })

      @machine.when(:paused,  :loading => :paused,  :playing => :paused)
      @machine.when(:stopped, :playing => :stopped, :paused  => :stopped)
      @machine.when(:played,  :playing => :played,  :paused  => :played)
    end
  end
end
