require "test_helper"
require "airplay/discovery/codec"

class CodecTest < Minitest::Test
  FIXTURES = {
    ptr: "000084000000000100000000085f616972706c6179045f746370056c6f63616c00000c00010000007800210b4c6976696e6720526f6f6d085f616972706c6179045f746370056c6f63616c00",
    srv: "0000840000000001000000000b4c6976696e6720526f6f6d085f616972706c6179045f746370056c6f63616c00002100010000007800190000000013880b6c6976696e672d726f6f6d056c6f63616c00",
    txt: "000084000000000100000000085f616972706c6179045f746370056c6f63616c00001000010000007800280e64657669636569643d41413a42421866656174757265733d307835413746464646372c30783145",
    a: "0000840000000001000000000b6c6976696e672d726f6f6d056c6f63616c0000010001000000780004c000020a",
    aaaa: "0000840000000001000000000b6c6976696e672d726f6f6d056c6f63616c00001c0001000000780010fe800000000000000000000000000001",
    unknown: "000084000000000100000000057468696e67056c6f63616c0000630001000000780003010203",
    truncated: "0000860000000001000000000b6c6976696e672d726f6f6d056c6f63616c0000010001000000780004c000"
  }.freeze

  def decode(name)
    Airplay::Discovery::Codec.decode([FIXTURES.fetch(name)].pack("H*"))
  end

  def test_decodes_ptr
    message = decode(:ptr)
    resource = message.resources.first

    assert_equal 1, message.qr
    assert_equal "_airplay._tcp.local", resource.name
    assert_equal 120, resource.ttl
    assert_equal "Living Room._airplay._tcp.local", resource.data.name.to_s
  end

  def test_decodes_srv
    resource = decode(:srv).resources.first

    assert_equal 5000, resource.data.port
    assert_equal "living-room.local", resource.data.target.to_s
  end

  def test_decodes_txt
    resource = decode(:txt).resources.first
    map = Airplay::Discovery::Codec.txt(resource.data.strings)

    assert_equal "AA:BB", map["deviceid"]
    assert_equal "0x5A7FFFF7,0x1E", map["features"]
  end

  def test_decodes_a_and_aaaa
    assert_equal "192.0.2.10", decode(:a).resources.first.data.address.to_s
    assert_equal "fe80::1", decode(:aaaa).resources.first.data.address.to_s
  end

  def test_keeps_unknown_record_data
    resource = decode(:unknown).resources.first

    assert_equal "\x01\x02\x03".b, resource.data.data
  end

  def test_rejects_truncated_messages
    error = assert_raises(Airplay::ProtocolError) { decode(:truncated) }

    assert_equal :truncated_mdns, error.code
  end

  def test_txt_splits_on_the_first_equals_and_preserves_binary
    map = Airplay::Discovery::Codec.txt(["a=1", "b=", "a=2", "bytes=\xFF".b])

    assert_equal "2", map["a"]
    assert_equal "", map["b"]
    assert_equal "\xFF".b, map["bytes"]
  end

  def test_txt_encoder_round_trips
    map = { "a" => "1", "empty" => "", "bin" => "\x01".b }
    decoded = Airplay::Discovery::Codec.txt(Airplay::Discovery::Codec.encode_txt(map))

    assert_equal map, decoded
  end

  def test_mutations_never_raise_unexpected_errors
    FIXTURES.each do |name, hex|
      bytes = [hex].pack("H*")

      [0, 1, 11, 12, bytes.bytesize - 1, bytes.bytesize / 2].uniq.each do |index|
        next if index.negative? || index >= bytes.bytesize

        mutated = bytes.dup
        mutated.setbyte(index, mutated.getbyte(index) ^ 0xFF)

        begin
          Airplay::Discovery::Codec.decode(mutated)
        rescue Airplay::ProtocolError
          nil
        rescue StandardError => error
          flunk "#{name} byte #{index} raised #{error.class}: #{error.message}"
        end
      end
    end
  end
end
