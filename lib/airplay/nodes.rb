require "forwardable"
require "airplay/node"

module Airplay
  # Public: Represents an array of nodes
  #
  class Nodes
    include Enumerable
    extend  Forwardable

    def_delegators :@items, :each, :size, :empty?

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
      find_by_block { |node| node if node.name == node_name }
    end

    def find_by_ip(ip)
      find_by_block { |node| node if node.ip == ip }
    end

    # Public: Adds a node to the list
    #
    #   value - The Node
    def <<(node)
      return if find_by_ip(node.ip)
      @items << node
    end

    private

    def find_by_block(&block)
      @items.find(&block)
    end

  end
end
