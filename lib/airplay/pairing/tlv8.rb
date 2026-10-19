require "airplay/errors"

module Airplay
  module Pairing
    # Public: TLV8 items used by every pairing exchange.
    module TLV8
      Item = Struct.new(:type, :value)

      class << self
        def encode(items)
          items.flat_map { |item| fragments(item.type, item.value) }
               .map { |item| [item.type, item.value.bytesize].pack("CC") + item.value.b }
               .join.b
        end

        def decode(bytes)
          data = bytes.to_s.b
          items = []
          offset = 0

          while offset < data.bytesize
            raise Airplay::ProtocolError.new("truncated TLV8 header", code: :malformed_tlv8) if offset + 2 > data.bytesize

            type = data.getbyte(offset)
            length = data.getbyte(offset + 1)
            value = data.byteslice(offset + 2, length)

            if value.nil? || value.bytesize != length
              raise Airplay::ProtocolError.new("truncated TLV8 value", code: :malformed_tlv8)
            end

            if items.last && items.last.type == type
              items.last.value << value
            else
              items << Item.new(type, value.dup)
            end

            offset += 2 + length
          end

          items
        end

        def fragments(type, value)
          bytes = value.to_s.b
          return [Item.new(type, "".b)] if bytes.empty?

          bytes.bytes.each_slice(255).map { |slice| Item.new(type, slice.pack("C*")) }
        end
      end
    end
  end
end
