require "test_helper"

class PairingNotesTest < Minitest::Test
  NOTES = File.read(File.expand_path("../../../doc/pairing.md", __dir__))
  SETUP = Airplay::Pairing::Setup
  RECEIVER = Airplay::FakeDevice::Receiver

  def test_flow_rows_match_the_source
    SETUP::FLOWS.each do |header, flow|
      cells = row("| `#{header}`")
      refute_nil cells, "missing flow row for #{header}"
      assert_equal RECEIVER::PAIRING_REQUESTS.fetch(flow).to_s, cells[3]
      assert_includes cells[4], SETUP::TRANSIENT_CODE if flow == :transient
    end

    cells = row("| —      | pair-verify")
    refute_nil cells, "missing pair-verify row"
    assert_equal RECEIVER::PAIRING_VERIFY_REQUESTS.to_s, cells[3]
  end

  def test_error_mapping_matches_the_source
    SETUP::ERRORS.each do |value, code|
      cells = row(format("| `0x%02x`", value))
      refute_nil cells, "missing error row for 0x#{format("%02x", value)}"
      assert_equal "`#{code}`", cells.last
    end
  end

  def test_event_and_feedback_notes_match_the_harness_knobs
    %i[events event_target event_write_key feedback_interval clock].each do |knob|
      assert_includes NOTES, "`#{knob}`"
    end
    assert_includes NOTES, "`eventPort`"
    assert_includes NOTES, "`feedbackInterval`"
    assert_includes NOTES, "POST /feedback"
  end

  def test_parameter_and_teardown_notes_match_the_source
    session = Airplay::Control::Session

    [0.0, 0.5, 1.0].each do |volume|
      assert_includes NOTES, session.decibels_for(volume).to_i.to_s
    end
    %w[SET_PARAMETER /command /teardown auth_required].each do |token|
      assert_includes NOTES, token
    end
    assert_includes NOTES, "metadata"
    assert_includes NOTES, "volume"
  end

  def test_credential_notes_match_the_store
    store = Airplay::Pairing::CredentialStore

    assert_includes NOTES, store::ENV_KEY
    assert_includes NOTES, format("%04o", store::DIRECTORY_MODE)
    assert_includes NOTES, format("%04o", store::FILE_MODE)
    assert_includes NOTES, "XDG_CONFIG_HOME"
    assert_includes NOTES, "binary plist"
    assert_includes NOTES, "Transient pairing writes nothing"
  end

  def test_route_notes_match_the_table
    route = Airplay::Route

    route::BITS.each { |name, bit| assert_includes NOTES, "`#{name}` (#{bit})" }
    route::FLAGS.each { |name, value| assert_includes NOTES, format("`%s` (0x%x)", name, value) }
    route::ROWS.each { |row| assert_includes NOTES, "`#{row[:name]}`" }
    assert_includes NOTES, "unsupported_feature"
    assert_includes NOTES, "override"
  end

  def test_the_notes_cover_the_whole_protocol_path
    %w[TLV8 pair-verify Event channel Credentials Route selection].each do |topic|
      assert_includes NOTES, topic
    end
    %w[PS-Msg05 PS-Msg06 PV-Msg02 PV-Msg03 3939 X-Apple-HKP].each do |token|
      assert_includes NOTES, token
    end
    assert_includes NOTES, "one-byte type"
    assert_includes NOTES, "2-byte little-endian"
    assert_includes NOTES, "four zero bytes"
  end

  def test_the_readme_deferred_list_matches_the_mechanisms
    readme = File.read(File.expand_path("../../../README.md", __dir__))

    Airplay::Pairing::Unsupported::MECHANISMS.each_value do |mechanism|
      assert_includes readme, mechanism
    end
    assert_includes readme, "PTP"
    assert_includes readme, "timing_error"
  end

  private

  def row(prefix)
    line = NOTES.lines.find { |candidate| candidate.start_with?(prefix) }
    line&.split("|")&.map(&:strip)&.reject(&:empty?)
  end
end
