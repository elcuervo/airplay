require "test_helper"

class RouteTest < Airplay::TestCase
  def features(*bits) = bits.sum { |bit| 1 << bit }

  def native_record(**options)
    { features: features(38, 46), credentials: true }.merge(options)
  end

  def test_the_decision_is_pure_and_uses_no_network
    with_receiver do |receiver|
      decision = Airplay::Route.decide(native_record)

      assert_equal :airplay2, decision.route
      assert_empty receiver.exchanges
    end
  end

  def test_an_unrelated_bit_does_not_change_the_route
    base = native_record
    assert_equal Airplay::Route.decide(base), Airplay::Route.decide(base.merge(features: base[:features] | (1 << 7)))
  end

  def test_a_paired_native_device_skips_pairing
    decision = Airplay::Route.decide(native_record)

    assert_equal :airplay2, decision.route
    assert_equal :capabilities, decision.source
    assert_equal %i[pair_verify info setup], decision.plan
  end

  def test_an_unpaired_native_device_starts_at_pair_setup
    decision = Airplay::Route.decide(native_record(credentials: false))

    assert_equal :airplay2, decision.route
    assert_equal :pair_setup, decision.plan.first
  end

  def test_a_password_flag_requires_a_password_before_any_request
    with_receiver(pairing: {}) do |receiver|
      error = assert_raises(Airplay::AuthRequiredError) do
        Airplay::Route.decide(native_record(pw: true))
      end

      assert_equal :auth_required, error.code
      assert_empty receiver.exchanges
      assert_equal :airplay2, Airplay::Route.decide(native_record(pw: true, password: "hunter2")).route
    end
  end

  def test_legacy_and_raop_routes
    legacy = Airplay::Route.decide({ features: features(0, 9) })
    assert_equal :airplay1, legacy.route
    assert_equal [:legacy_auth], legacy.plan

    raop = Airplay::Route.decide({ features: features(9), raop: true })
    assert_equal :raop, raop.route
    assert_equal [:raop], raop.plan
  end

  def test_hints_follow_the_advertised_bits
    rich = Airplay::Route.decide(native_record(features: features(38, 46, 41, 40, 49)))
    plain = Airplay::Route.decide(native_record)

    assert_equal %i[ptp buffered v2], [rich.timing, rich.stream, rich.video]
    assert_equal %i[ntp realtime legacy], [plain.timing, plain.stream, plain.video]
  end

  def test_an_override_short_circuits_the_table
    decision = Airplay::Route.decide(native_record, override: :legacy)

    assert_equal :airplay1, decision.route
    assert_equal :override, decision.source
    assert_equal [:legacy_auth], decision.plan
  end

  def test_an_impossible_override_is_rejected
    error = assert_raises(Airplay::UnsupportedError) do
      Airplay::Route.decide({ features: features(38) }, override: :airplay2)
    end

    assert_equal :unsupported_feature, error.code
    assert_includes error.message, "AirPlay 2 native"
  end

  def test_airplay2_capability_beats_legacy_video
    decision = Airplay::Route.decide(native_record(features: features(0, 9, 38, 46)))

    assert_equal :airplay2, decision.route
  end

  def test_a_failed_native_pairing_issues_no_legacy_request
    with_receiver(pairing: { accept: false }) do |receiver|
      decision = Airplay::Route.decide(native_record(credentials: false))
      assert_equal :pair_setup, decision.plan.first

      assert_raises(Airplay::AuthFailedError) do
        Airplay.sync { Airplay::Pairing::Setup.pair(receiver.device, attempts: 1) }
      end

      assert_equal ["/pair-setup"], receiver.exchanges.map(&:path).uniq
    end
  end
end
