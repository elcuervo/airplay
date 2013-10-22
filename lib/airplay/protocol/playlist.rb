require "forwardable"

module Airplay
  module Protocol
    class Playlist
      include Enumerable
      extend  Forwardable

      def_delegators :@items, :each, :size, :empty?, :<<

      def initialize
        @items = []
        @position = 0
      end

      def to_ary
        @items
      end

      def next
        return nil if @position + 1 > @items.size

        item = @items[@position]
        @position += 1
        item
      end

      def previous
        return nil if @position - 1 < 0

        @position -= 1
        @items[@position]
      end
    end
  end
end
