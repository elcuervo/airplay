require "airplay/protocol/player"

module Airplay
  module Playable

    # Public: Plays a given video
    #
    #   file_or_url - The video to be played
    #   options - Optional start position
    #
    # Returns a Player object to control the playback
    #
    def play(file_or_url = "playlist", options = {})
      player.async.play(file_or_url, options)
      player
    end

    def playlist
      player.playlist
    end

    private

    def player
      @_player ||= Airplay::Protocol::Player.new(self)
    end
  end
end
