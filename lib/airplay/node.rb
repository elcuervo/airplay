require "airplay/structure"

module Airplay
  class Node < Structure.new(:name, :address, :domain)
    class Info < Structure.new(:deviceid, :features, :model, :srcvers); end

    class Features < Structure.new(:video, :photo, :video_fair_play,
                                :video_volume_control, :video_http_live_stream,
                                :slideshow, :screen, :screen_rotate, :audio,
                                :audio_redundant, :FPSAPv2pt5_AES_GCM,
                                :photo_caching)
      def self.load(features)
        create(
          video:                  0 < (features & ( 1 <<  0 )),
          photo:                  0 < (features & ( 1 <<  1 )),
          video_fair_play:        0 < (features & ( 1 <<  2 )),
          video_volume_control:   0 < (features & ( 1 <<  3 )),
          video_http_live_stream: 0 < (features & ( 1 <<  4 )),
          slideshow:              0 < (features & ( 1 <<  5 )),
          screen:                 0 < (features & ( 1 <<  7 )),
          screen_rotate:          0 < (features & ( 1 <<  8 )),
          audio:                  0 < (features & ( 1 <<  9 )),
          audio_redundant:        0 < (features & ( 1 << 11 )),
          FPSAPv2pt5_AES_GCM:     0 < (features & ( 1 << 12 )),
          photo_caching:          0 < (features & ( 1 << 13 ))
        )
      end
    end

    attr_accessor :features, :ip, :port, :info, :features

    def initialize(*)
      super
      parse_address
    end

    def parse_info(info)
      @info = Info.create(info)
      @features = Features.load(info.fetch("features", "0").hex)
    end

    private

    def parse_address
      @ip, port = address.split(":")
      @port = port.to_i
    end
  end
end
