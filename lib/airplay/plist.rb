require "plist"
require "stringio"

require "airplay/errors"

module Airplay
  # Public: Binary property list codec used by the AirPlay 2 control plane.
  module Plist
    Data = Struct.new(:bytes)
    EPOCH = Time.utc(2001, 1, 1).freeze
    MAX_DOCUMENT_SIZE = 8 * 1024 * 1024
    MAX_DEPTH = 100

    class DecodeError < Airplay::ProtocolError
      def self.code = :malformed_plist
    end

    class << self
      def dump(value)
        Binary.encode(value)
      end

      def load(data)
        Binary.decode(data)
      end

      def dump_xml(value)
        XML.encode(value)
      end

      def load_xml(xml)
        XML.decode(xml)
      end
    end

    # Public: `bplist00` encoder and decoder.
    module Binary
      HEADER = "bplist00".b

      class << self
        def encode(value)
          Encoder.new(value).encode
        end

        def decode(data)
          Decoder.new(data).decode
        end
      end

      class Encoder
        def initialize(value)
          @objects = []
          assign(value)
        end

        def encode
          bodies = @objects.map { |value| body(value) }
          offset_size = integer_width(bodies.sum(&:bytesize))
          ref_size = integer_width(@objects.length - 1)
          offsets = []
          position = HEADER.bytesize

          bodies.each do |bytes|
            offsets << pack_integer(position, offset_size)
            position += bytes.bytesize
          end

          offset_table_offset = position
          table = offsets.join.b
          num_objects = @objects.length
          top_object = 0
          trailer = ("\0" * 6).b + [offset_size, ref_size].pack("CC") +
                    [num_objects, top_object, offset_table_offset].pack("Q>Q>Q>")

          HEADER + bodies.join.b + table + trailer
        end

        private

        def assign(value)
          id = @objects.length
          @objects << value

          case value
          when Array
            value.each { |item| assign(item) }
          when Hash
            value.keys.sort_by { |key| key.to_s.b }.each do |key|
              assign(key)
              assign(value[key])
            end
          end

          id
        end

        def body(value)
          case value
          when nil then [0x00].pack("C")
          when true then [0x09].pack("C")
          when false then [0x08].pack("C")
          when Integer then integer_body(value)
          when Float then [0x23].pack("C") + [value].pack("G")
          when Time then [0x33].pack("C") + [value - EPOCH].pack("G")
          when Data then length_marker(0x40, value.bytes.bytesize) + value.bytes.b
          when String then string_body(value)
          when Array
            length_marker(0xA0, value.length) +
              value.map { |item| pack_integer(id_of(item), ref_size) }.join.b
          when Hash
            keys = value.keys.sort_by { |key| key.to_s.b }
            length_marker(0xD0, keys.length) +
              keys.map { |key| pack_integer(id_of(key), ref_size) }.join.b +
              keys.map { |key| pack_integer(id_of(value[key]), ref_size) }.join.b
          else
            raise Airplay::ProtocolError.new("unsupported plist value #{value.class}", code: :unsupported_plist_value)
          end
        end

        def id_of(value)
          @objects.index { |candidate| candidate.equal?(value) } ||
            raise(Airplay::ProtocolError.new("unassigned plist object", code: :unsupported_plist_value))
        end

        def string_body(value)
          if value.ascii_only?
            length_marker(0x50, value.bytesize) + value.b
          else
            encoded = value.encode("UTF-16BE")
            length_marker(0x60, encoded.bytesize / 2) + encoded.b
          end
        end

        def integer_body(value)
          if value.negative?
            [0x13].pack("C") + [value].pack("q>")
          elsif value <= 0xFF
            [0x10].pack("C") + [value].pack("C")
          elsif value <= 0xFFFF
            [0x11].pack("C") + [value].pack("S>")
          elsif value <= 0xFFFFFFFF
            [0x12].pack("C") + [value].pack("L>")
          else
            [0x13].pack("C") + [value].pack("Q>")
          end
        end

        def length_marker(marker, length)
          if length < 15
            [marker | length].pack("C")
          else
            [marker | 0x0F].pack("C") + integer_body(length)
          end
        end

        def ref_size
          @ref_size ||= integer_width(@objects.length - 1)
        end

        def integer_width(value)
          return 1 if value <= 0xFF
          return 2 if value <= 0xFFFF
          return 4 if value <= 0xFFFFFFFF

          8
        end

        def pack_integer(value, width)
          case width
          when 1 then [value].pack("C")
          when 2 then [value].pack("S>")
          when 4 then [value].pack("L>")
          else [value].pack("Q>")
          end
        end
      end

      class Decoder
        def initialize(data)
          @data = data.to_s.b
        end

        def decode
          validate_document!
          @offset_size = @data.getbyte(@data.bytesize - 26)
          @ref_size = @data.getbyte(@data.bytesize - 25)
          @num_objects, @top_object, @offset_table_offset =
            @data.byteslice(@data.bytesize - 24, 24).unpack("Q>Q>Q>")
          validate_trailer!
          @offsets = read_offsets
          @objects = {}
          decode_object(@top_object, 0)
        end

        private

        def validate_document!
          if @data.bytesize < HEADER.bytesize + 32
            raise DecodeError.new("plist is too short", code: :malformed_plist)
          end
          if @data.bytesize > MAX_DOCUMENT_SIZE
            raise DecodeError.new("plist exceeds the maximum size", code: :malformed_plist)
          end
          unless @data.byteslice(0, HEADER.bytesize) == HEADER
            raise DecodeError.new("missing bplist00 header", code: :malformed_plist)
          end
        end

        def validate_trailer!
          unless [1, 2, 4, 8].include?(@offset_size) && [1, 2, 4, 8].include?(@ref_size)
            raise DecodeError.new("invalid trailer widths", code: :malformed_plist)
          end
          raise DecodeError.new("empty object table", code: :malformed_plist) if @num_objects.zero?
          raise DecodeError.new("top object out of range", code: :malformed_plist) if @top_object >= @num_objects

          expected = @offset_table_offset + (@num_objects * @offset_size) + 32
          unless expected == @data.bytesize
            raise DecodeError.new("over-declared object count", code: :malformed_plist)
          end
          if @offset_table_offset < HEADER.bytesize || @offset_table_offset > @data.bytesize - 32
            raise DecodeError.new("invalid offset table", code: :malformed_plist)
          end
        end

        def read_offsets
          Array.new(@num_objects) do |index|
            position = @offset_table_offset + (index * @offset_size)
            value = unpack_table_integer(position, @offset_size)
            if value >= @offset_table_offset
              raise DecodeError.new("object offset outside the object table", code: :malformed_plist)
            end
            value
          end
        end

        def unpack_table_integer(position, width)
          if position.negative? || position + width > @data.bytesize - 32
            raise DecodeError.new("offset table is truncated", code: :malformed_plist)
          end

          bytes = @data.byteslice(position, width)
          case width
          when 1 then bytes.unpack1("C")
          when 2 then bytes.unpack1("S>")
          when 4 then bytes.unpack1("L>")
          when 8 then bytes.unpack1("Q>")
          else raise DecodeError.new("unsupported integer width", code: :malformed_plist)
          end
        end

        def decode_object(id, depth)
          raise DecodeError.new("plist nesting is too deep", code: :malformed_plist) if depth > MAX_DEPTH
          return @objects[id] if @objects.key?(id)

          guard = (@visiting ||= {})
          raise DecodeError.new("cyclic plist object", code: :malformed_plist) if guard[id]
          guard[id] = true

          offset = @offsets.fetch(id)
          marker = @data.getbyte(offset)
          type = marker >> 4
          info = marker & 0x0F
          value =
            case type
            when 0x0 then marker == 0x00 ? nil : marker == 0x08 ? false : marker == 0x09 ? true : unsupported(marker)
            when 0x1 then read_integer(offset + 1, info)
            when 0x2 then read_real(offset + 1, info)
            when 0x3 then read_date(offset + 1, info)
            when 0x4 then read_data(offset, info)
            when 0x5 then read_ascii(offset, info)
            when 0x6 then read_utf16(offset, info)
            when 0xA then read_array(offset, info, depth)
            when 0xD then read_dictionary(offset, info, depth)
            else unsupported(marker)
            end

          @objects[id] = value
          guard.delete(id)
          value
        end

        def read_integer(position, info)
          width = 1 << info
          raise DecodeError.new("unsupported integer width", code: :malformed_plist) if width > 8

          value = unpack_integer(position, width)
          value -= (1 << 64) if width == 8 && value >= (1 << 63)
          value
        end

        def read_real(position, info)
          case info
          when 2 then @data.byteslice(position, 4).unpack1("g")
          when 3 then @data.byteslice(position, 8).unpack1("G")
          else raise DecodeError.new("unsupported real width", code: :malformed_plist)
          end
        end

        def read_date(position, info)
          raise DecodeError.new("unsupported date marker", code: :malformed_plist) unless info == 3

          EPOCH + @data.byteslice(position, 8).unpack1("G")
        end

        def read_data(offset, info)
          length, position = read_length(offset, info)
          Data.new(checked_byteslice(position, length))
        end

        def read_ascii(offset, info)
          length, position = read_length(offset, info)
          checked_byteslice(position, length).force_encoding("UTF-8")
        end

        def read_utf16(offset, info)
          length, position = read_length(offset, info)
          checked_byteslice(position, length * 2).force_encoding("UTF-16BE").encode("UTF-8")
        end

        def read_array(offset, info, depth)
          length, position = read_length(offset, info)
          refs = Array.new(length) { |index| unpack_integer(position + (index * @ref_size), @ref_size) }
          refs.map { |ref| decode_object(ref, depth + 1) }
        end

        def read_dictionary(offset, info, depth)
          length, position = read_length(offset, info)
          key_refs = Array.new(length) { |index| unpack_integer(position + (index * @ref_size), @ref_size) }
          value_position = position + (length * @ref_size)
          value_refs = Array.new(length) { |index| unpack_integer(value_position + (index * @ref_size), @ref_size) }

          key_refs.each_with_index.each_with_object({}) do |(key_ref, index), hash|
            key = decode_object(key_ref, depth + 1)
            raise DecodeError.new("dictionary key is not a string", code: :malformed_plist) unless key.is_a?(String)

            hash[key] = decode_object(value_refs[index], depth + 1)
          end
        end

        def read_length(offset, info)
          if info == 0x0F
            marker = @data.getbyte(offset + 1)
            raise DecodeError.new("missing extended length", code: :malformed_plist) if marker.nil? || (marker >> 4) != 1

            width = 1 << (marker & 0x0F)
            [unpack_integer(offset + 2, width), offset + 2 + width]
          else
            [info, offset + 1]
          end
        end

        def unpack_integer(position, width)
          bytes = checked_byteslice(position, width)
          case width
          when 1 then bytes.unpack1("C")
          when 2 then bytes.unpack1("S>")
          when 4 then bytes.unpack1("L>")
          when 8 then bytes.unpack1("Q>")
          else raise DecodeError.new("unsupported integer width", code: :malformed_plist)
          end
        end

        def checked_byteslice(position, length)
          if position.negative? || length.negative? || position + length > @offset_table_offset
            raise DecodeError.new("plist reads past the object table", code: :malformed_plist)
          end
          @data.byteslice(position, length)
        end

        def unsupported(marker)
          raise DecodeError.new(format("unsupported plist marker 0x%02x", marker), code: :malformed_plist)
        end
      end
    end

    # Public: XML representation via the `plist` gem, sharing the binary value model.
    module XML
      class << self
        def encode(value)
          ::Plist::Emit.dump(export(value))
        end

        def decode(xml)
          import(::Plist.parse_xml(xml, marshal: false))
        end

        private

        def export(value)
          case value
          when Data then StringIO.new(value.bytes.b)
          when Time then value.utc
          when Array then value.map { |item| export(item) }
          when Hash then value.to_h { |key, item| [key, export(item)] }
          else value
          end
        end

        def import(value)
          case value
          when DateTime then value.to_time.utc
          when StringIO then Data.new(value.string.b)
          when Array then value.map { |item| import(item) }
          when Hash then value.to_h { |key, item| [key, import(item)] }
          else value
          end
        end
      end
    end
  end
end
