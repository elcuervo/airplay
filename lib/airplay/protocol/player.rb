require "uri"
require "forwardable"
require "micromachine"

module Airplay::Protocol
  class Player
    extend Forwardable
    include Celluloid

    def_delegators :@machine, :state, :on

    def initialize
      @machine = MicroMachine.new(:stopped)

      @machine.when(:loading, :stopped => :loading)
      @machine.when(:playing, :paused  => :playing, :loading => :playing, :stopped => :playing)
      @machine.when(:paused,  :loading => :paused,  :playing => :paused)
      @machine.when(:stopped, :playing => :played,  :paused  => :played)

      @machine.on(:played) { stop }

      @callback = proc do |event|
        @machine.trigger(event["state"].to_sym) if event["category"] == "video"
      end
    end

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

    def scrub
      return unless playing?
      response = Airplay.connection.get("/scrub")
      parts = response.body.split("\n")
      Hash[parts.collect { |v| v.split(": ") }]
    end

    def resume
      Airplay.connection.async.post("/rate?value=1")
    end

    def pause
      Airplay.connection.async.post("/rate?value=0")
    end

    def stop
      Airplay.stop
    end

    def playing?; state == :playing end
    def paused?;  state == :paused  end
    def played?;  state == :played  end
    def stopped?; state == :stopped end

    def wait
      sleep 0.1 while !played?
      stop
    end

    private

    def add_events_callback
      if !Airplay.connection.reverse.callbacks.include?(@callback)
        Airplay.connection.reverse.callbacks << @callback
      end
    end

  end
end
