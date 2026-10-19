require "test_helper"
require "airplay/pairing/tlv8"
require "json"

class TLV8Test < Minitest::Test
  VECTOR = JSON.parse(File.read("test/fixtures/pairing/tlv8_vector.json"))

  def test_hand_authored_vector
    items = VECTOR["items"].map do |item|
      Airplay::Pairing::TLV8::Item.new(item["type"], [item["value"]].pack("H*"))
    end

    encoded = Airplay::Pairing::TLV8.encode(items)

    assert_equal VECTOR["encoded"], encoded.unpack1("H*")
    assert_equal items, Airplay::Pairing::TLV8.decode(encoded)
  end

  def test_small_items_round_trip_in_order
    items = [
      Airplay::Pairing::TLV8::Item.new(0x00, "\x00"),
      Airplay::Pairing::TLV8::Item.new(0x06, "\x01"),
      Airplay::Pairing::TLV8::Item.new(0x63, "unknown")
    ]

    decoded = Airplay::Pairing::TLV8.decode(Airplay::Pairing::TLV8.encode(items))

    assert_equal items, decoded
  end

  def test_unknown_types_survive
    bytes = "\x63\x03\x01\x02\x03".b

    decoded = Airplay::Pairing::TLV8.decode(bytes)

    assert_equal 0x63, decoded.first.type
    assert_equal "\x01\x02\x03".b, decoded.first.value
    assert_equal bytes, Airplay::Pairing::TLV8.encode(decoded)
  end

  def test_600_byte_value_is_fragmented_and_reassembled
    value = ("A" * 600).b
    encoded = Airplay::Pairing::TLV8.encode([Airplay::Pairing::TLV8::Item.new(0x03, value)])

    lengths = []
    offset = 0
    while offset < encoded.bytesize
      lengths << encoded.getbyte(offset + 1)
      offset += 2 + encoded.getbyte(offset + 1)
    end

    assert_equal [255, 255, 90], lengths
    assert_equal value, Airplay::Pairing::TLV8.decode(encoded).first.value
  end

  def test_fragments_are_not_merged_across_a_different_type
    first = Airplay::Pairing::TLV8::Item.new(0x03, "one")
    separator = Airplay::Pairing::TLV8::Item.new(0x04, "x")
    second = Airplay::Pairing::TLV8::Item.new(0x03, "two")
    decoded = Airplay::Pairing::TLV8.decode(
      Airplay::Pairing::TLV8.encode([first, separator, second])
    )

    assert_equal 3, decoded.length
    assert_equal "one", decoded[0].value
    assert_equal "two", decoded[2].value
  end

  def test_truncated_item_raises
    error = assert_raises(Airplay::ProtocolError) do
      Airplay::Pairing::TLV8.decode("\x03\x05ab")
    end

    assert_equal :malformed_tlv8, error.code
  end
end
