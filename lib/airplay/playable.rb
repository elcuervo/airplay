require "airplay/player"

module Airplay
  module Playable
    # Public: Plays a given video
    #
    # file_or_url - The video to be played
    # options - Optional start position
    #
    # Returns a Player object to control the playback
    #
    def play(file_or_url = "playlist", options = {})
      player.async.play(file_or_url, options)
      player
    end

    # Public: Gets the current playlist
    #
    # Returns the Playlist
    #
    def playlist
      player.playlist
    end

    # Public: Gets all the playlists
    #
    # Returns the Playlists
    #
    def playlists
      player.playlists
    end

    # Public: Gets the player object
    #
    # Returns a Player object
    def player
      @_player ||= Airplay::Player.new(self)
    end
  end
end
