module Airplay
  class Player
    class Media
      attr_reader :url

      def initialize(file_or_url)
        @url = case true
               when File.exists?(file_or_url)
                 Airplay.server.serve(File.expand_path(file_or_url))
               when !!(file_or_url =~ URI::regexp)
                 file_or_url
               else
                 raise Errno::ENOENT, file_or_url
               end
      end

      def to_s
        @url
      end
    end
  end
end
