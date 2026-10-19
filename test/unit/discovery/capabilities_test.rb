require "test_helper"
require "airplay/discovery/capabilities"

class CapabilitiesTest < Minitest::Test
  def capabilities(txt)
    Airplay::Discovery::Capabilities.new(txt)
  end

  def test_decodes_two_word_mask
    assert_equal 0x0008030040000a00, capabilities("features" => "0x40000a00,0x80300").mask
  end

  def test_decodes_single_word_and_ft_fallback
    assert_equal 0x1e, capabilities("features" => "0x1e").mask
    assert_equal 0x1e, capabilities("ft" => "0x1e").mask
  end

  def test_malformed_mask_is_unknown
    model = capabilities("features" => "zz")

    assert_nil model.mask
    refute model.video?
    refute model.airplay2?
  end

  def test_password_pin_and_legacy_predicates
    assert capabilities("pw" => "true").password_required?
    assert capabilities("sf" => "0x80").password_required?
    refute capabilities("sf" => "0x80").pin_required?
    model = capabilities("sf" => "0x208")

    assert model.pin_required?
    assert model.legacy_pairing?
  end

  def test_version_comparison_is_segment_wise
    version = capabilities("srcvers" => "354.54.6").srcvers

    assert_operator version, :>=, "354.54.6"
    assert_operator version, :>=, "354.5"
    assert_operator version, :<, "355"
    assert_nil capabilities("srcvers" => "beta").srcvers
  end

  def test_identity_group_and_access_fields
    model = capabilities(
      "deviceid" => "AA:BB:CC:DD:EE:FF",
      "pi" => "PI",
      "psi" => "PSI",
      "pk" => "KEY",
      "gid" => "GROUP+1+OTHER",
      "pgid" => "PARENT+1",
      "tsid" => "TSID",
      "gpn" => "Name",
      "igl" => "1",
      "gcgl" => "0",
      "acl" => "1",
      "act" => "2",
      "rsf" => "0"
    )

    assert_equal "AA:BB:CC:DD:EE:FF", model.device_id
    assert_equal "PI", model.identity
    assert_equal "KEY", model.public_key
    assert_equal "GROUP", model.group_id
    assert_equal "PARENT", model.parent_group_id
    assert_equal "TSID", model.tight_sync_id
    assert_equal "Name", model.group_public_name
    assert model.group_leader?
    refute model.group_connected_leader?
    assert model.restricted_access?
    assert_equal "2", model.act
    assert_equal "0", model.rsf
  end

  def test_media_predicates
    model = capabilities("features" => "0x5A7FFFF7,0x1E")

    assert model.video?
    assert model.photo?
    assert model.slideshow?
    assert model.screen?
    assert model.audio?
  end

  def test_video_v2_and_control_predicates
    model = capabilities("features" => "0x0,0x34c40")

    assert model.video_v2?
    assert model.unified_media_control?
    assert model.pairing?
    assert model.airplay2?
    assert model.transient_pairing?
  end

  def test_version_gated_streaming_predicates
    buffered = capabilities("features" => "0x0,0x100", "srcvers" => "354.54.6")

    assert buffered.buffered_audio?
    refute capabilities("features" => "0x0,0x100", "srcvers" => "354.54.5").buffered_audio?
    refute capabilities("features" => "0x0,0x100").buffered_audio?

    ptp = capabilities("features" => "0x0,0x200", "srcvers" => "366.0")

    assert ptp.ptp?
    refute capabilities("features" => "0x0,0x200", "srcvers" => "365.9").ptp?
  end

  def test_unreadable_group_and_unknown_acl_do_not_fail
    model = capabilities("gid" => "", "acl" => "99")

    assert_nil model.group_id
    assert_equal "99", model.acl
    refute model.restricted_access?
  end

  def test_unknown_keys_are_preserved
    model = capabilities("cn" => "0,1", "et" => "0,3,5", "future" => "value")

    assert_equal "0,1", model.txt["cn"]
    assert_equal "0,3,5", model.txt["et"]
    assert_equal "value", model.txt["future"]
  end

  def test_authoritative_refresh_replaces_values_and_reports_source
    txt = capabilities("features" => "0x1,0x0", "srcvers" => "100")
    live = txt.refresh("features" => "0x40000a00,0x80300", "srcvers" => "354.54.6")

    assert_equal 0x0008030040000a00, live.mask
    assert_equal :authoritative, live.source(:mask)
    assert_equal :authoritative, live.source(:srcvers)
    assert_equal "0x1,0x0", live.txt["features"]
    assert_equal %w[features srcvers], live.disagreements
  end

  def test_a_reconciliation_without_disagreement_lists_nothing
    txt = capabilities("features" => "0x1,0x0", "srcvers" => "354.54.6")
    live = txt.refresh("srcvers" => "354.54.6")

    assert_equal :authoritative, live.source(:srcvers)
    assert_empty live.disagreements
  end
end
