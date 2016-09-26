module Airplay
  # Public: Represents an Airplay Device
  #
  class Device
    # Public: Simple class to represent information of a Device
    #
    class Info
      attr_reader :model, :os_version, :mac_address

      def initialize(device)
        @device = device
        @model = device.server_info["model"]
        @os_version = device.server_info["srcvers"]
        @mac_address = device.server_info["macAddress"]
      end

      def resolution
        @_resolution ||= begin
          return "unknown" if @device.server_info["width"].nil?

          "#{@device.server_info["width"]}x#{@device.server_info["height"]}"
        end
      end
    end
  end
end
