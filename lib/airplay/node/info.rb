module Airplay
  # Public: Represents an Airplay Node
  #
  class Node
    # Public: Simple class to represent information of a Node
    #
    class Info
      attr_reader :model, :os_version, :mac_address

      def initialize(node)
        @node = node
        @model = node.server_info["model"]
        @os_version = node.server_info["osBuildVersion"]
        @mac_address = node.server_info["macAddress"]
      end

      def resolution
        @_resolution ||= "#{@node.server_info["width"]}x#{@node.server_info["height"]}"
      end
    end
  end
end
