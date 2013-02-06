require "open-uri"

module Airplay::Protocol
  # Public: The class to handle image broadcast to a device
  #
  class Image
    def initialize(media_or_io, options = {})
      @content = get_content(media_or_io)
      @transition = options.fetch(:transition, "None")
    end

    # Public: Broadcasts the content to the device
    #
    def broadcast
      Airplay.connection.put("/photo", @content, {
        "X-Apple-Transition" => @transition
      })
    end

    private

    # Private: Gets the content of the possible media_or_io
    #
    #   media_or_io - The url, file, path or read compatible source
    #
    def get_content(media_or_io)
      case true
      when File.exists?(File.expand_path(media_or_io))
        File.read(media_or_io)
      when !!(media_or_io =~ URI::regexp)
        open(media_or_io).read
      when media_or_io.is_a?(String)
        media_or_io
      when media_or_io.respond_to?(:read)
        media_or_io.read
      end
    end
  end
end
