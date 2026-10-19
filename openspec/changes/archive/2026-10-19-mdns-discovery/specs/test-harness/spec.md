# Spec Delta

## ADDED Requirements

### Requirement: Discovery in-process mDNS responder double

The test harness SHALL provide an mDNS responder double that advertises configurable service
instances — instance name, service type, SRV target, port, TTL and address family — over the
multicast destinations on an interface usable in tests, without external services, and records
every query it receives with its source and decoded contents.

```ruby
Airplay.sync do
  responder = Airplay::FakeDevice::MDNSResponder.new(
    port: 55_353, interfaces: ["lo0"]
  ).start

  responder.advertise(
    name: "Living Room",
    type: "_airplay._tcp.local.",
    target: "living-room.local.",
    port: 7000,
    txt: { "deviceid" => "AA:BB:CC:DD:EE:FF", "features" => "0x5A7FDFD5,0x3C155FDE" }
  )

  result = Airplay::Discovery::Browser.new(
    port: 55_353, interfaces: ["lo0"]
  ).browse(window: 0.5)

  result.records.first.port # => 7000
  responder.stop
end
```

#### Scenario: Discoverable without system services

- **WHEN** a test starts the responder double with one configured instance and browses
- **THEN** the instance is discovered with no system daemon installed and no external network used

#### Scenario: Received traffic is inspectable

- **WHEN** a test asks the responder double for the traffic it recorded
- **THEN** each entry exposes the source address, the arrival order and the decoded query or answer

### Requirement: Discovery harness fault injection

The responder double SHALL support per-test discovery faults: withholding or delaying an instance's
SRV answer, answering with a TXT record that conflicts with an earlier answer for the same instance,
answering only on IPv6, and dropping a configured fraction of answers.

```ruby
responder.advertise(
  name: "Silent",
  type: "_airplay._tcp.local.",
  target: "silent.local.",
  port: 7000,
  fault: :withhold_srv
)

responder.advertise(
  name: "Lossy",
  type: "_airplay._tcp.local.",
  target: "lossy.local.",
  port: 7000,
  drop: 0.5
)
```

#### Scenario: Withheld SRV answer

- **WHEN** the responder withholds SRV answers for an instance it announced
- **THEN** the browse result contains no record for that instance

#### Scenario: Conflicting TXT answer

- **WHEN** the responder answers the second query for an instance with a different TXT map
- **THEN** the record reflects the newer map once its TTL has replaced the earlier one

#### Scenario: IPv6-only answer

- **WHEN** the responder is configured to answer only on the IPv6 multicast group
- **THEN** the instance is discovered with an IPv6 address

#### Scenario: Dropped answers

- **WHEN** the responder drops a configured fraction of its answers
- **THEN** the browse still returns within its window and the responder's log shows the retry queries
