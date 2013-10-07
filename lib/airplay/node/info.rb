module Airplay
  # Public: Represents an Airplay Node
  #
  class Node
    # Public: Simple class to represent information of a Node
    #
    class Info
      attr_reader :model, :os_version

      def initialize(node)
        @model = node.server_info["model"]
        @os_version = node.server_info["osBuildVersion"]
      end
    end
  end
end
