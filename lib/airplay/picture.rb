require "uri"

require "airplay/errors"
require "airplay/media"

module Airplay
  # Public: Resolves the documented picture inputs into bytes and a content type.
  module Picture
    class << self
      def resolve(input, session:)
        case input
        when String
          bytes = input.dup.force_encoding(Encoding::BINARY)
          if !bytes.include?("\0") && File.file?(input)
            [File.binread(input), Airplay::Media.type_for(input)]
          elsif bytes.match?(%r{\Ahttps?://}i)
            response = session.fetch(input)
            unless response.status.between?(200, 299)
              raise Airplay::PlaybackError.new("picture URL answered #{response.status}",
                                               status: response.status)
            end

            [response.body.to_s.b, response.headers["content-type"] || "application/octet-stream"]
          else
            [input.dup.b, "image/jpeg"]
          end
        else
          if input.respond_to?(:read)
            [input.read.to_s.b, "image/jpeg"]
          else
            raise Airplay::PlaybackError.new("unsupported picture #{input.class}", code: :playback_error)
          end
        end
      end
    end
  end
end
