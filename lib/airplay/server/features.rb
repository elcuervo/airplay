class Airplay::Server::Features
 attr_reader :Video,
             :Photo,
             :VideoFairPlay,
             :VideoVolumeControl,
             :VideoHTTPLiveStreams,
             :Slideshow,
             :Screen,
             :ScreenRotate,
             :Audio,
             :AudioRedundant,
             :FPSAPv2pt5_AES_GCM,
             :PhotoCaching

  def initialize(features)
    @Video                = 0 < (features & ( 1 <<  0 ))
    @Photo                = 0 < (features & ( 1 <<  1 ))
    @VideoFairPlay        = 0 < (features & ( 1 <<  2 ))
    @VideoVolumeControl   = 0 < (features & ( 1 <<  3 ))
    @VideoHTTPLiveStreams = 0 < (features & ( 1 <<  4 ))
    @Slideshow            = 0 < (features & ( 1 <<  5 ))
    @Screen               = 0 < (features & ( 1 <<  7 ))
    @ScreenRotate         = 0 < (features & ( 1 <<  8 ))
    @Audio                = 0 < (features & ( 1 <<  9 ))
    @AudioRedundant       = 0 < (features & ( 1 << 11 ))
    @FPSAPv2pt5_AES_GCM   = 0 < (features & ( 1 << 12 ))
    @PhotoCaching         = 0 < (features & ( 1 << 13 ))
  end
end
