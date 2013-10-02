require "airplay/node"

module Airplay
  # Public: Represents an array of nodes
  #
  class Nodes
    include Enumerable

    def initialize
      @items = []
    end

    # Public: Finds a node given a name
    #
    #   node_name - The name of the node
    #
    # Returns a Node object
    #
    def find_by_name(node_name)
      find_by_block { |node| node.name == node_name }
    end

    def find_by_ip(ip)
      find_by_block { |node| node.ip == ip }
    end

    def find_by_block(&block)
      @items.find(&block)
    end

    # Public: Iterates through all the nodes
    #
    def each(&block)
      @items.each(&block)
    end

    # Public: Adds a node to the list
    #
    #   value - The Node
    def <<(node)
      return if find_by_ip(node.ip)
      @items << node
    end

    # Public: The current size of the node list
    #
    def size
      @items.size
    end
  end
end
