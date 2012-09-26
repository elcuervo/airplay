require "airplay/node"

module Airplay
  class Nodes
    include Enumerable

    def initialize
      @items = []
    end

    def find_by_name(node_name)
      @items.find { |node| node.name == node_name }
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
