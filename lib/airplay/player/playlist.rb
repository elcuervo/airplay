require "forwardable"
require "airplay/player/media"

module Airplay
  class Player
    class Playlist
      include Enumerable
      extend  Forwardable

      attr_reader :name

      def_delegators :@items, :each, :size, :empty?

      def initialize(name)
        @name = name
        @items = []
        @position = 0
      end

      def to_ary
        @items
      end

      def <<(file_or_url)
        @items << Media.new(file_or_url)
      end

      def next?;     @position + 1 <= @items.size end
      def previous?; @position - 1 >= 0 end

      def next
        return nil if !next?

        item = @items[@position]
        @position += 1
        item
      end

      def previous
        return nil if !previous?

        @position -= 1
        @items[@position]
      end
    end
  end
end
