require "test_helper"
require "airplay/cli"

class DiscoveryProtocolTest < Airplay::TestCase
  PORT = 55_353

  def setup
    super
    Airplay.configure do |config|
      config.discovery_port = PORT
      config.discovery_interfaces = ["lo0"]
      config.discovery_window = 1.0
    end
  end

  def with_responder(**attributes)
    Airplay.sync do
      responder = Airplay::FakeDevice::MDNSResponder.new(
        port: PORT, interfaces: ["lo0"]
      ).start

      begin
        responder.advertise(**attributes)
        yield responder
      ensure
        responder.stop
      end
    end
  end

  def browser(**options)
    Airplay::Discovery::Browser.new(
      **{ port: PORT, interfaces: ["lo0"] }.merge(options)
    )
  end

  def test_discovers_an_airplay_instance
    with_responder(
      name: "Living Room",
      port: 5000,
      txt: { "deviceid" => "AA:BB", "features" => "0x5A7FFFF7,0x1E" }
    ) do |_responder|
      result = browser.browse(window: 1.0, force: true)

      assert_equal :data_available, result.reason
      assert_equal 1, result.records.length
      record = result.records.first
      assert_equal "Living Room", record.name
      assert_equal "_airplay._tcp.local.", record.service_type
      assert_equal 5000, record.port
      assert_equal "127.0.0.1", record.host
      assert_equal "AA:BB", record.txt["deviceid"]
      assert record.capabilities.video?
    end
  end

  def test_discovers_a_raop_instance_and_splits_the_identifier
    with_responder(
      name: "AA:BB@Kitchen",
      type: "_raop._tcp.local.",
      port: 5001
    ) do |_responder|
      record = browser.browse(window: 1.0, force: true).records.first

      assert_equal "Kitchen", record.display_name
      assert_equal "AA:BB", record.identifier
      assert_equal "_raop._tcp.local.", record.service_type
      assert_equal 5001, record.port
      assert_empty record.txt
    end
  end

  def test_cache_reuse_sends_no_second_query
    with_responder(name: "Cached", port: 7000) do |responder|
      discovery = browser
      first = discovery.browse(window: 1.0, force: true)
      queries = responder.received.length

      second = discovery.browse(window: 1.0)

      assert_equal first.records.map(&:name), second.records.map(&:name)
      assert_equal queries, responder.received.length
    end
  end

  def test_expiry_triggers_a_new_query
    clock = Airplay::FakeDevice::FakeClock.new
    with_responder(name: "Expiring", port: 7000, ttl: 120) do |responder|
      discovery = browser(clock: clock)
      discovery.browse(window: 1.0, force: true)
      queries = responder.received.length

      clock.advance(121)
      discovery.browse(window: 1.0)

      assert_operator responder.received.length, :>, queries
    end
  end

  def test_goodbye_removes_the_instance
    with_responder(name: "Leaving", port: 7000) do |responder|
      discovery = browser
      discovery.browse(window: 1.0, force: true)

      Airplay.sync do |task|
        pending = task.async { discovery.browse(window: 0.5, force: true) }
        sleep(0.05)
        responder.unadvertise("Leaving")
        result = pending.wait

        assert_empty result.records
      end
    end
  end

  def test_withheld_srv_yields_no_record
    with_responder(name: "Silent", port: 7000, fault: :withhold_srv) do |_responder|
      result = browser.browse(window: 0.5, force: true)

      assert_empty result.records
      assert_equal :window_elapsed, result.reason
    end
  end

  def test_conflicting_txt_replaces_the_cached_map
    with_responder(
      name: "Changing",
      port: 7000,
      txt: { "srcvers" => "354.54.6" },
      conflicting_txt: { "srcvers" => "366.0" }
    ) do |_responder|
      discovery = browser
      discovery.browse(window: 1.0, force: true)
      record = discovery.browse(window: 1.0, force: true).records.first

      assert_equal "366.0", record.txt["srcvers"]
    end
  end

  def test_ipv6_only_answer_yields_an_ipv6_address
    with_responder(name: "Six", port: 7000, fault: :ipv6_only, address6: "fe80::1") do |_responder|
      record = browser.browse(window: 1.0, force: true).records.first

      assert_equal [:ipv6], record.addresses.map(&:family).uniq
      assert_equal "fe80::1", record.preferred_address.ip
      assert_equal "lo0", record.preferred_address.scope
      assert_includes record.preferred_address.to_s, "%lo0"
    end
  end

  def test_dropped_answers_still_return_within_the_window
    with_responder(name: "Lossy", port: 7000, drop: 1.0) do |responder|
      result = browser.browse(window: 1.0, force: true)

      assert_empty result.records
      assert_equal :window_elapsed, result.reason
      assert_operator responder.received.length, :>=, 2
    end
  end

  def test_cancellation_ends_the_browse
    with_responder(name: "Cancelled", port: 7000) do |_responder|
      discovery = browser
      Airplay.sync do |task|
        browse = task.async { discovery.browse(window: 2.0, force: true) }
        sleep(0.05)
        discovery.cancel!
        result = browse.wait

        assert_equal :cancelled, result.reason
      end
    end
  end

  def test_empty_network_is_an_empty_result
    result = browser(port: 55_399).browse(window: 0.2, force: true)

    assert_empty result.records
    assert_equal :window_elapsed, result.reason
  end

  def test_devices_on_an_empty_network_is_empty_and_does_not_raise
    Airplay.configure do |config|
      config.discovery_port = 55_397
      config.discovery_window = 0.1
    end

    assert_empty Airplay.devices.to_a
  end

  def test_missing_interface_is_a_transport_error
    error = assert_raises(Airplay::TransportError) do
      Airplay::Discovery::Browser.new(
        port: PORT, interfaces: ["nope0"]
      ).browse(window: 0.1)
    end

    assert_equal :interface_unavailable, error.code
  end

  def test_devices_enumeration_and_lookup
    with_responder(name: "Living Room", port: 7000, txt: { "deviceid" => "AA:BB" }) do |_responder|
      devices = Airplay.devices
      devices.browse(window: 1.0, force: true)

      assert_equal 1, devices.count
      assert_equal "Living Room", devices["Living Room"].display_name
      assert_equal "Living Room", Airplay["Living Room"].display_name
      assert_equal "AA:BB", devices.find_by_identifier("AA:BB").capabilities.device_id
      assert_equal "127.0.0.1", devices.find_by_address("127.0.0.1").host
    end
  end

  def test_sender_only_sends_queries
    with_responder(name: "Quiet", port: 7000) do |responder|
      browser.browse(window: 0.5, force: true)

      assert responder.received.all? { |entry| entry.message.qr.zero? }
    end
  end

  def test_advertised_address_override
    Airplay.configure { |config| config.advertised_address = "203.0.113.10" }

    with_responder(name: "Natted", port: 7000) do |_responder|
      record = browser.browse(window: 1.0, force: true).records.first

      assert_equal "203.0.113.10", record.advertised_address
      assert_equal "127.0.0.1", record.preferred_address.ip
    end
  end

  def test_two_browses_progress_while_answers_are_delayed
    with_responder(name: "Delayed", port: 7000, fault: :delay_srv) do |_responder|
      Airplay.sync do |task|
        first = task.async { browser.browse(window: 1.0, force: true) }
        second = task.async { browser.browse(window: 1.0, force: true) }

        assert_equal 1, first.wait.records.length
        assert_equal 1, second.wait.records.length
      end
    end
  end

  def test_cancelled_browse_leaves_no_sockets_or_queries
    with_responder(name: "Cancel", port: 7000) do |responder|
      discovery = browser
      Airplay.sync do |task|
        pending = task.async { discovery.browse(window: 2.0, force: true) }
        sleep(0.05)
        discovery.cancel!
        pending.wait
      end

      assert_empty discovery.instance_variable_get(:@sockets)
      before = responder.received.length
      Airplay.sync { |task| sleep(0.2) }
      assert_equal before, responder.received.length
    end
  end

  def test_doctor_reports_a_discovered_device
    with_responder(
      name: "Living Room",
      port: 5000,
      txt: { "deviceid" => "AA:BB", "features" => "0x5A7FFFF7,0x1E" }
    ) do |_responder|
      output, = capture_io { Airplay.sync { assert Airplay::CLI.run(["doctor"]) } }

      assert_match(/Living Room/, output)
      assert_match(/video/, output)
      assert_match(/5000/, output)
    end
  end
end
