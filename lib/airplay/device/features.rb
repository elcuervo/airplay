module Airplay
  # Public: Represents an Airplay Node
  #
  class Device
    # Public: The feature list of a given device
    #
    class Features
      attr_reader :properties

      def initialize(device)
        @device = device
        check_features
      end

      private

      def check_features
        hex = @device.server_info["features"].to_s.hex
        @properties = {
          video?:                   0 < (hex & ( 1 <<  0 )),
          photo?:                   0 < (hex & ( 1 <<  1 )),
          video_fair_play?:         0 < (hex & ( 1 <<  2 )),
          video_volume_control?:    0 < (hex & ( 1 <<  3 )),
          video_http_live_streamr?: 0 < (hex & ( 1 <<  4 )),
          slideshow?:               0 < (hex & ( 1 <<  5 )),
          screen?:                  0 < (hex & ( 1 <<  7 )),
          screen_rotate?:           0 < (hex & ( 1 <<  8 )),
          audio?:                   0 < (hex & ( 1 <<  9 )),
          audio_redundant?:         0 < (hex & ( 1 << 11 )),
          FPSAPv2pt5_AES_GCM?:      0 < (hex & ( 1 << 12 )),
          photo_caching?:           0 < (hex & ( 1 << 13 ))
        }

        @properties.each do |key, value|
          self.class.send(:define_method, key) { value }
        end

      end

    end

  end
end
