require "test_helper"
require "airplay/discovery/service_record"

class ServiceRecordTest < Airplay::TestCase
  def record(addresses)
    Airplay::Discovery::ServiceRecord.new(
      name: "Living Room",
      service_type: "_airplay._tcp.local.",
      target: "living-room.local.",
      port: 7000,
      addresses: addresses,
      txt: { "deviceid" => "AA:BB" },
      ttl: 120
    )
  end

  def test_prefers_ipv4_over_ipv6_and_link_local_last
    ipv6 = Airplay::Discovery::Address.new(
      ip: "2001:db8::1", family: :ipv6, interface: "en0"
    )
    link_local = Airplay::Discovery::Address.new(
      ip: "fe80::1", family: :ipv6, interface: "en0", scope: "en0"
    )
    ipv4 = Airplay::Discovery::Address.new(
      ip: "192.0.2.10", family: :ipv4, interface: "en0"
    )

    assert_equal "192.0.2.10", record([link_local, ipv6, ipv4]).preferred_address.ip
    assert_equal "2001:db8::1", record([link_local, ipv6]).preferred_address.ip
    assert_equal "fe80::1%en0", record([link_local]).preferred_address.to_s
  end

  def test_splits_a_raop_identifier
    raop = Airplay::Discovery::ServiceRecord.new(
      name: "AA:BB@Kitchen",
      service_type: "_raop._tcp.local.",
      target: "kitchen.local.",
      port: 5001,
      addresses: [],
      txt: {},
      ttl: 120
    )

    assert_equal "Kitchen", raop.display_name
    assert_equal "AA:BB", raop.identifier
  end

  def test_one_record_carries_addresses_from_two_interfaces
    first = Airplay::Discovery::Address.new(
      ip: "192.0.2.10", family: :ipv4, interface: "en0"
    )
    second = Airplay::Discovery::Address.new(
      ip: "192.0.2.11", family: :ipv4, interface: "en1"
    )

    resolved = record([first, second])

    assert_equal 2, resolved.addresses.length
    assert_equal %w[en0 en1], resolved.addresses.map(&:interface)
    assert_equal "192.0.2.10", resolved.preferred_address.ip
  end

  def test_advertised_address_override_is_independent_of_the_bound_address
    Airplay.configure { |config| config.advertised_address = "203.0.113.10" }
    address = Airplay::Discovery::Address.new(
      ip: "192.0.2.10", family: :ipv4, interface: "en0"
    )

    assert_equal "203.0.113.10", record([address]).advertised_address
    assert_equal "192.0.2.10", record([address]).preferred_address.ip
  end
end
