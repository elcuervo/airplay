require "open-uri"

require "airplay/loggable"

module Airplay
  # Public: The class to handle image broadcast to a device
  #
  class Viewer
    UnsupportedType = Class.new(TypeError)

    TRANSITIONS = %w(None Dissolve SlideLeft SlideRight)

    include Loggable

    def initialize(device)
      @device = device
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

      log.debug "Fetched content (#{content.bytesize} bytes)"
      log.debug "PUT /photo with transition: #{transition}"

      response = connection.put("/photo", content, {
        "Content-Length" => content.bytesize.to_s,
        "X-Apple-Transition" => transition
      })

      response.response.code == "200"
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
      when is_binary?(media_or_io) then media_or_io
      when is_file?(media_or_io)   then File.read(media_or_io)
      when is_url?(media_or_io)    then open(media_or_io).read
      when is_string?(media_or_io) then media_or_io
      when is_io?(media_or_io)     then media_or_io.read
      else raise UnsupportedType.new("That media type is unsupported")
      end
    end

    # Private: Check if the string is binary
    #
    # string - The string to be checked
    #
    # Returns true/false
    #
    def is_binary?(string)
      string.encoding.names.include?("BINARY")
    rescue
      false
    end

    # Private: Check if the string is in the filesystem
    #
    # string - The string to be checked
    #
    # Returns true/false
    #
    def is_file?(string)
      return false if string.is_a?(StringIO)
      !File.directory?(string) && File.exists?(File.expand_path(string))
    rescue
      false
    end

    # Private: Check if the string is a URL
    #
    # string - The string to be checked
    #
    # Returns true/false
    #
    def is_url?(string)
      !!(string =~ URI::regexp)
    rescue
      false
    end

    # Private: Check if the string is actually a string
    #
    # string - The string to be checked
    #
    # Returns true/false
    #
    def is_string?(string)
      string.is_a?(String)
    end

    # Private: Check if the string can be read
    #
    # string - The string to be checked
    #
    # Returns true/false
    #
    def is_io?(string)
      string.respond_to?(:read)
    end
  end
end
