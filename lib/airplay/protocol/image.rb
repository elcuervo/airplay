module Airplay::Protocol
  # Public: The class to handle image broadcast to a device
  #
  class Image
    def initialize(media_or_io, options = {})
      @content = File.read(media_or_io)
    end

    # Public: Broadcasts the content to the device
    #
    def broadcast
      Airplay.connection.post("/photo", @content)
    end
  end
end
