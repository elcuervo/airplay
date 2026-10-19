# service-discovery Specification

## Purpose
Find and resolve AirPlay and RAOP receivers on the local network with an in-process mDNS
implementation, so every other capability reads structured, cache-consistent service records
instead of parsing `host:port` strings out of a system discovery daemon.

## Requirements

### Requirement: Multicast browsing on IPv4 and IPv6

Discovery SHALL query the mDNS multicast destinations `224.0.0.251:5353` (IPv4) and `ff02::fb:5353`
(IPv6) and SHALL accept answers arriving on either family, so a responder reachable over only one
family is still discovered.

```ruby
result = Airplay::Discovery::Browser.new(port: 55353).browse(window: 0.5, families: [:ipv4, :ipv6])
result.records.first.addresses.map { |address| [address.family, address.ip] }
# => [[:ipv4, "192.0.2.10"]]
```

#### Scenario: IPv4-only responder

- **WHEN** a responder answers only on the IPv4 multicast group
- **THEN** its service instance appears in the browse result with its IPv4 address

#### Scenario: IPv6-only responder

- **WHEN** a responder answers only on the IPv6 multicast group
- **THEN** its service instance appears in the browse result with its IPv6 address

### Requirement: Both AirPlay service types

Discovery SHALL browse `_airplay._tcp.local.` and `_raop._tcp.local.` and SHALL report the service
type each result was resolved from, so routing can prefer the AirPlay endpoint and still reach
RAOP-only receivers.

```ruby
Airplay::Discovery::SERVICE_TYPES
# => ["_airplay._tcp.local.", "_raop._tcp.local."]

record.service_type # => "_airplay._tcp.local."
record.display_name # => "Living Room"
```

#### Scenario: AirPlay endpoint resolved

- **WHEN** a responder advertises `_airplay._tcp.local.`
- **THEN** the record reports that service type

#### Scenario: RAOP-only receiver resolved

- **WHEN** a responder advertises only `_raop._tcp.local.` with the `<identifier>@<name>` instance
  name shape the ecosystem uses
- **THEN** the record is reported once, with the identifier separated from the display name

### Requirement: Resolution through SRV, TXT and address records

A record SHALL carry the hostname and port from the SRV answer, the decoded key/value map from the
TXT answer and the addresses from the A and AAAA answers. An instance SHALL be reported only once an
SRV answer and at least one address are known; a missing or late TXT answer SHALL still yield the
record, with an empty key/value map, rather than withholding it.

```ruby
record.target  # => "living-room.local."
record.port    # => 7000
record.txt     # => {"deviceid"=>"AA:BB:CC:DD:EE:FF", "features"=>"0x5A7FDFD5,0x3C155FDE"}
record.addresses.map(&:ip) # => ["192.0.2.10"]
```

#### Scenario: SRV answer arrives late

- **WHEN** a responder announces an instance and sends its SRV answer only after the query window
  started
- **THEN** the instance is absent from the result until the SRV answer arrives and present afterwards

#### Scenario: TXT answer missing

- **WHEN** a responder publishes an instance with no TXT answer
- **THEN** the record is reported with an empty key/value map and its host and port

### Requirement: Port taken from SRV

Every record's port SHALL be the port from its own SRV answer, and discovery SHALL NOT assume,
default to or fall back to port 7000 or any other fixed port.

```ruby
record.port # => 5000 (from SRV; never a hard-coded 7000)
```

#### Scenario: Receiver on a non-default port

- **WHEN** a responder advertises its instance on SRV port 5000
- **THEN** the record's port is 5000 and a caller connecting to that record targets port 5000

### Requirement: Structured service records

Results SHALL be records exposing the service instance name, the service type, the SRV target
hostname, the resolved addresses, the SRV port, the decoded TXT map and the record TTL as separate
values, so reading a port never requires parsing a host string.

```ruby
record.name          # => "Living Room"
record.service_type  # => "_airplay._tcp.local."
record.target        # => "living-room.local."
record.port          # => 7000
record.addresses     # => [#<Address ip="192.0.2.10" family=:ipv4 interface="en0">]
record.txt           # => {"deviceid"=>"...", "features"=>"..."}
record.ttl           # => 120
record.capabilities  # => #<Airplay::Discovery::Capabilities ...>
```

#### Scenario: Record exposes separate values

- **WHEN** a caller reads a resolved device
- **THEN** host, port, addresses and TXT keys are available as independent values

#### Scenario: No concatenated address

- **WHEN** a caller reads a resolved device's port, hostname or addresses
- **THEN** no returned value embeds a port suffix in an address string

### Requirement: TTL-aware caching

Records SHALL be cached for the TTL of the answer that produced them. A lookup inside that lifetime
SHALL be served from the cache without sending a query, an expired record SHALL be resolved again,
and an answer with TTL 0 SHALL remove the instance from subsequent results.

```ruby
browser = Airplay::Discovery::Browser.new(cache: cache, clock: fake_clock)
browser.browse(window: 0.2) # sends the first query
browser.browse(window: 0.2) # served from cache, no query sent

fake_clock.advance(121)
browser.browse(window: 0.2) # cache expired, queries again
```

#### Scenario: Cache reuse

- **WHEN** two lookups happen inside the TTL of the first answer
- **THEN** the responder receives only the first lookup's query

#### Scenario: Refresh after expiry

- **WHEN** the injected clock passes the cached record's TTL and the caller looks up again
- **THEN** a new query is sent and the refreshed answer replaces the cached record

#### Scenario: Goodbye removes the instance

- **WHEN** a responder publishes a TTL-0 record for an instance it had advertised
- **THEN** that instance no longer appears in enumeration

### Requirement: Interface selection and multi-homed hosts

Discovery SHALL send its queries on each selected interface and SHALL retain the interface each
answer arrived on. An instance answering on several interfaces or families SHALL produce one record
carrying all its addresses, and the record's preferred address SHALL be deterministic: an address on
a receiving interface, IPv4 before IPv6, link-local last.

```ruby
browser = Airplay::Discovery::Browser.new(interfaces: ["lo0"])
record.addresses.map { |a| [a.interface, a.family, a.ip] }
# => [["lo0", :ipv4, "192.0.2.10"], ["lo0", :ipv6, "fe80::1%lo0"]]
record.preferred_address.ip # => "192.0.2.10"
```

#### Scenario: Same instance on two interfaces

- **WHEN** one instance answers on two interfaces with different addresses
- **THEN** enumeration contains one record for it listing both addresses

#### Scenario: Preferred address is deterministic

- **WHEN** a record holds both an IPv4 and a non-link-local IPv6 address on a receiving interface
- **THEN** the preferred address is the IPv4 one, and repeating the browse does not change which
  address is preferred

#### Scenario: Link-local address keeps its scope

- **WHEN** the only answer for an instance carries a link-local IPv6 address
- **THEN** the record reports that address together with its scope identifier

### Requirement: Advertised address override

Callers SHALL be able to configure the address the library advertises to receivers, independently of
the interface and address discovery resolved, so a host behind NAT or a container bridge reports a
reachable address while still binding its sockets to the local one.

```ruby
Airplay.configure { |config| config.advertised_address = "203.0.113.10" }
record.advertised_address # => "203.0.113.10"
record.preferred_address.ip # => "192.0.2.10" (the bound local address)
```

#### Scenario: Override is reported instead of the resolved address

- **WHEN** the advertised address is configured to a value that differs from the discovered address
- **THEN** the record's advertised address is the configured value while the socket's local address
  remains the discovered interface address

### Requirement: Bounded browse with observable outcomes

Browsing SHALL run for a caller-bounded window and SHALL return a result carrying the records found
and the reason it ended (data available, window elapsed, or cancelled). Finding no devices SHALL be a
result with no records and no raised error, never a timeout exception.

```ruby
result = Airplay::Discovery::Browser.new(port: 55353).browse(window: 0.2)

result.records # => []
result.reason  # => :window_elapsed
```

#### Scenario: No responders present

- **WHEN** a caller browses on a network with no responder and no other mDNS traffic
- **THEN** the call returns an empty result within the configured window without raising

#### Scenario: Cancellation ends the browse promptly

- **WHEN** a caller cancels a browse that is still waiting
- **THEN** the call returns promptly with the records found so far and the cancelled reason

### Requirement: Transport failure is distinguishable

When discovery cannot create its sockets or join the multicast groups, it SHALL fail with the
runtime's transport error carrying its machine-readable code, so callers distinguish a broken local
configuration from an empty network.

```ruby
begin
  Airplay::Discovery::Browser.new(interfaces: ["nope0"]).browse(window: 0.2)
rescue Airplay::TransportError => error
  error.code # => :interface_unavailable
end
```

#### Scenario: Unusable interface

- **WHEN** a caller browses on an interface name that does not exist
- **THEN** the call raises the transport error with its documented code instead of returning an empty
  result

### Requirement: Enumeration and lookup

`Airplay.devices` SHALL enumerate the current records, lookups SHALL find a device by its advertised
display name and by its address or identifier, and discovering the same instance again SHALL NOT add
a duplicate entry.

```ruby
Airplay.devices.each { |device| puts device.display_name }

Airplay.devices["Living Room"]              # by display name
Airplay.devices.find_by_identifier("AA:BB") # by identifier
```

#### Scenario: Lookup by display name

- **WHEN** a responder advertises the display name `Apple TV` and a caller looks that name up
- **THEN** the matching record is returned

#### Scenario: Autodiscovery disabled

- **WHEN** the caller disables autodiscovery and enumerates devices with a populated cache
- **THEN** no query is sent and the cached records are enumerated

#### Scenario: Repeated browse does not duplicate

- **WHEN** the same instance is discovered twice within its TTL
- **THEN** enumeration contains one record for it

### Requirement: The sender never advertises

The library SHALL NOT register, publish, announce or answer mDNS services: its discovery sockets
SHALL only send queries and consume answers.

```ruby
# The library's socket has no answer path: this is the whole outbound API.
browser.query(service_type) # sends a PTR question, returns nothing
```

#### Scenario: Sender sends only queries

- **WHEN** a caller browses while the harness responder records every packet it receives
- **THEN** all received packets are queries and none is a response or an unsolicited announcement

#### Scenario: Incoming query is not answered

- **WHEN** the harness responder sends a service query to the library's discovery socket
- **THEN** the library sends no response
