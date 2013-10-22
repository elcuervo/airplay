module Airplay
  class Group
    class Players
      attr_reader :players

      def initialize(players)
        @players = players
      end

      def progress(callback)
        players.each do |player|
          player.progress -> info {
            callback.call(player.device, info) if player.playing?
          }
        end
      end

      def wait
        sleep 0.1 while still_playing?
        players.map(&:cleanup)
      end

      private

      def still_playing?
        states = players.map { |player| !player.played? || player.stopped? }
        states.uniq == [true]
      end
    end
  end
end
