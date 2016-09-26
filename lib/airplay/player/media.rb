require "mime/types"

require "airplay/server"

module Airplay
  class Player
    class Media
      attr_reader :file_or_url, :url

      COMPATIBLE_TYPES = %w(
        application/mp4
        video/mp4
        video/vnd.objectvideo
        video/MP2T
        video/quicktime
        video/mpeg4
      )

      def initialize(file_or_url)
        @file_or_url = file_or_url
      end

      def url
        @_url ||= case true
                 when local?
                   Airplay.server.serve(File.expand_path(file_or_url))
                 when remote?
                   file_or_url
                 else
                   raise Errno::ENOENT, file_or_url
                 end
      end

      def compatible?
        @_compatible ||= begin
          path = File.basename(file_or_url)
          compatibility = MIME::Types.type_for(path).map(&:to_s) & COMPATIBLE_TYPES
          compatibility.any?
        end
      end

      def local?
        File.exists?(file_or_url)
      end

      def remote?
        !!(file_or_url =~ URI::regexp)
      end

      alias to_s url
    end
  end
end
