module Airplay
  module Discovery
    # Public: A dotted numeric version compared segment by segment.
    class Version
      include Comparable

      def self.parse(value)
        return value if value.is_a?(self)
        return nil if value.nil?

        segments = value.to_s.split(".").map do |segment|
          Integer(segment, 10)
        rescue ArgumentError
          return nil
        end
        return nil if segments.empty?

        new(value.to_s, segments)
      end

      attr_reader :raw, :segments

      def initialize(raw, segments)
        @raw = raw
        @segments = segments.freeze
      end

      def <=>(other)
        other = self.class.parse(other) unless other.is_a?(self.class)
        return nil unless other

        width = [segments.length, other.segments.length].max
        left = segments + Array.new(width - segments.length, 0)
        right = other.segments + Array.new(width - other.segments.length, 0)
        left <=> right
      end

      def to_s
        raw
      end

      def inspect
        "#<#{self.class} #{raw}>"
      end
    end
  end
end
