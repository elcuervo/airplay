module Airplay::Protocol
  PlaybackInfo = Struct.new(:info) do
    def uuid
      info["uuid"]
    end

    def duration
      info["duration"]
    end

    def position
      info["position"]
    end

    def percent
      (position * 100 / duration).floor
    end

    def likely_to_keep_up?
      info["playbackLikelyToKeepUp"]
    end

    def stall_count
      info["stallCount"]
    end

    def ready_to_play?
      info["readyToPlay"]
    end

    def stopped?
      info.empty?
    end

    def playing?
      info.has_key?("rate") && info.fetch("rate", false) && !info["rate"].zero?
    end

    def played?
      # This is weird. I know. Bear with me.
      info.keys.size == 2
    end
  end
end
