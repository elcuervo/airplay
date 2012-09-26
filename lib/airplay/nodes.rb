require "airplay/node"

module Airplay
  class Nodes
    include Enumerable

    def initialize
      @items = []
    end

    def each(&block)
      @items.each(&block)
    end

    def <<(value)
      @items << value
    end

    def size
      @items.size
    end
  end
end
