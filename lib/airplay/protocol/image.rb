module Airplay::Protocol
  class Image
    def initialize(media_or_io, options = {})
      @content = File.read(media_or_io)
    end

    def broadcast
      Airplay.connection.post("/photo", @content)
    end
  end
end
