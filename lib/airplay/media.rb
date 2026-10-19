require "fileutils"

require "airplay/errors"

module Airplay
  # Public: Media value objects and the local media server.
  module Media
    TYPES = {
      ".mov" => "video/quicktime",
      ".mp4" => "video/mp4",
      ".m4v" => "video/x-m4v",
      ".avi" => "video/x-msvideo",
      ".mkv" => "video/x-matroska",
      ".mp3" => "audio/mpeg",
      ".m4a" => "audio/mp4",
      ".aac" => "audio/aac",
      ".wav" => "audio/wav",
      ".jpg" => "image/jpeg",
      ".jpeg" => "image/jpeg",
      ".png" => "image/png",
      ".gif" => "image/gif",
      ".webp" => "image/webp"
    }.freeze
    DEFAULT_TYPE = "application/octet-stream"

    class << self
      def type_for(path)
        TYPES.fetch(File.extname(path.to_s).downcase, DEFAULT_TYPE)
      end

      def image?(path)
        type_for(path).start_with?("image/")
      end

      def compatible?(path)
        type = type_for(path)
        type.start_with?("video/", "audio/", "image/")
      end
    end

    # Public: One playable item.
    class Media
      attr_reader :source, :url, :type

      def initialize(source: nil, url: nil)
        @source = source
        @url = url
        @type = source ? Airplay::Media.type_for(source) : nil
      end

      def local? = !@source.nil?
      def compatible? = local? ? Airplay::Media.compatible?(@source) : true
      def to_s = (@url || @source).to_s
    end

    # Public: A queue of media with current-item navigation.
    class Playlist
      include Enumerable

      def initialize(items = [])
        @items = items.dup
        @index = 0
      end

      def each(&block) = @items.each(&block)
      def size = @items.length
      def empty? = @items.empty?
      def <<(item) = (@items << item; self)
      def current = @items[@index]
      def use(index) = (@index = index; current)

      def next_item
        return nil if empty?

        @items[(@index + 1) % size].tap { @index = (@index + 1) % size }
      end

      def previous
        return nil if empty?

        @items[(@index - 1) % size].tap { @index = (@index - 1) % size }
      end
    end
  end
end
