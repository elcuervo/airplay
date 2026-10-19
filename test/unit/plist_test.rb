require "test_helper"
require "airplay/plist"
require "json"
require "open3"
require "tempfile"

class PlistTest < Minitest::Test
  def sample
    {
      "null" => nil,
      "true" => true,
      "false" => false,
      "one" => 255,
      "two" => 256,
      "four" => 70_000,
      "eight" => 2**32,
      "negative" => -5,
      "float" => 1.5,
      "date" => Time.utc(2020, 1, 2, 3, 4, 5),
      "data" => Airplay::Plist::Data.new("\x00\xFF\x01".b),
      "ascii" => "hello",
      "unicode" => "héllo 世界",
      "array" => [1, "two", { "x" => 3 }],
      "nested" => { "a" => [true, false], "b" => { "c" => 42 } }
    }
  end

  def test_round_trip_every_type
    encoded = Airplay::Plist.dump(sample)
    decoded = Airplay::Plist.load(encoded)

    assert_equal sample, decoded
  end

  def test_nested_containers_round_trip
    value = [[{ "a" => [1, 2] }], { "b" => { "c" => ["d"] } }]

    assert_equal value, Airplay::Plist.load(Airplay::Plist.dump(value))
  end

  def test_encoding_is_deterministic_and_key_order_independent
    first = Airplay::Plist.dump(sample)
    second = Airplay::Plist.dump(sample)
    reordered = Airplay::Plist.dump(sample.to_a.reverse.to_h)

    assert_equal first, second
    assert_equal first, reordered
  end

  def test_date_is_an_absolute_instant
    date = Time.utc(2001, 1, 1, 0, 0, 1)
    decoded = Airplay::Plist.load(Airplay::Plist.dump({ "date" => date }))["date"]

    assert_equal date, decoded.utc
  end

  def test_truncated_document_raises
    encoded = Airplay::Plist.dump(sample)

    assert_raises(Airplay::Plist::DecodeError) do
      Airplay::Plist.load(encoded.byteslice(0, encoded.bytesize - 5))
    end
  end

  def test_over_declared_object_count_raises
    encoded = Airplay::Plist.dump(sample)
    over_declared = encoded.dup
    count_offset = over_declared.bytesize - 24
    count = over_declared.byteslice(count_offset, 8).unpack1("Q>")
    over_declared[count_offset, 8] = [count + 1].pack("Q>")

    assert_raises(Airplay::Plist::DecodeError) { Airplay::Plist.load(over_declared) }
  end

  def test_unsupported_marker_raises
    encoded = Airplay::Plist.dump({ "a" => 1 })
    unsupported = encoded.dup
    unsupported.setbyte(8, 0x70)

    error = assert_raises(Airplay::Plist::DecodeError) { Airplay::Plist.load(unsupported) }
    assert_match(/unsupported plist marker/, error.message)
  end

  def test_oversized_document_raises
    data = "bplist00".b + ("\0" * (Airplay::Plist::MAX_DOCUMENT_SIZE + 1))

    assert_raises(Airplay::Plist::DecodeError) { Airplay::Plist.load(data) }
  end

  def test_xml_fixture_round_trips_through_the_value_model
    value = Airplay::Plist.load_xml(File.read("test/fixtures/pairing/sample.xml.plist"))

    assert_equal [1, "two"], value["array"]
    assert_equal({ "a" => 3 }, value["dict"])
    assert_equal Time.utc(2020, 1, 2, 3, 4, 5), value["date"]
    assert_equal "\x00\xFF\x01".b, value["data"].bytes
    assert_equal "héllo 世界", value["unicode"]
    assert_equal value, Airplay::Plist.load_xml(Airplay::Plist.dump_xml(value))
    assert_equal value, Airplay::Plist.load(Airplay::Plist.dump(value))
  end

  def test_reads_an_independent_binary_fixture
    data = File.binread("test/fixtures/pairing/sample.bplist")
    expected = JSON.parse(File.read("test/fixtures/pairing/sample.json"))
    value = Airplay::Plist.load(data)

    assert_equal expected["ascii"], value["ascii"]
    assert_equal expected["unicode"], value["unicode"]
    assert_equal expected["integer"], value["integer"]
    assert_equal expected["negative"], value["negative"]
    assert_equal expected["real"], value["real"]
    assert_equal expected["true"], value["true"]
    assert_equal expected["false"], value["false"]
    assert_equal Time.utc(2020, 1, 2, 3, 4, 5), value["date"].utc
    assert_equal [expected["data"]].pack("H*"), value["data"].bytes
    assert_equal expected["array"], value["array"]
    assert_equal expected["dict"], value["dict"]
  end

  def test_plutil_reads_the_binary_output
    skip "plutil is not available" unless system("command -v plutil > /dev/null 2>&1")

    file = Tempfile.new(["airplay", ".plist"])
    file.binmode
    file.write(Airplay::Plist.dump({ "a" => 1, "b" => "héllo" }))
    file.close

    output, error, status = Open3.capture3("plutil", "-convert", "xml1", "-o", "-", file.path)

    assert status.success?, error
    assert_includes output, "<integer>1</integer>"
    assert_includes output, "héllo"
  ensure
    file&.unlink
  end

  def test_encoding_is_byte_identical_across_processes
    script = <<~RUBY
      require "airplay/plist"
      value = { "b" => 2, "a" => 1, "c" => [true, nil, "x"] }
      print Airplay::Plist.dump(value).unpack1("H*")
    RUBY

    first, first_status = Open3.capture2("ruby", "-Ilib", "-e", script)
    second, second_status = Open3.capture2("ruby", "-Ilib", "-e", script)

    assert first_status.success?
    assert second_status.success?
    assert_equal first, second
  end
end
