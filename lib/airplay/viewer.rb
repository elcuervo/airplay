require "open-uri"

module Airplay
  # Public: The class to handle image broadcast to a device
  #
  class Viewer
    TRANSITIONS = %w(None Dissolve SlideLeft SlideRight)

    def initialize(device)
      @device = device
      @logger = Airplay::Logger.new("airplay::viewer")
    end

    # Public: Broadcasts the content to the device
    #
    # media_or_io - The url, file path or io of the image/s
    # options     - Options that include the device
    #               * transition: the type of transition (Default: None)
    #
    # Returns if the images was actually sent
    #
    def view(media_or_io, options = {})
      content = get_content(media_or_io)
      transition = options.fetch(:transition, "None")

      @logger.info "Fetched content (#{content.bytesize} bytes)"
      @logger.debug "PUT /photo with transition: #{transition}"

      response = connection.put("/photo", content, {
        "Content-Length" => content.bytesize.to_s,
        "X-Apple-Transition" => transition
      })

      response.response.status == 200
    end

    # Public: The list of transitions
    #
    # Returns the list of trasitions
    #
    def transitions; TRANSITIONS end

    private

    # Public: The connection
    #
    # Returns the connection
    #
    def connection
      @_connection ||= Airplay::Connection.new(@device)
    end

    # Private: Gets the content of the possible media_or_io
    #
    # media_or_io - The url, file, path or read compatible source
    #
    # Returns the content of the media
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
