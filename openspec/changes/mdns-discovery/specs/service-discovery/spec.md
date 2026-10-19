# Spec Delta

## Purpose

Find and resolve AirPlay and RAOP receivers on the local network with an in-process mDNS
implementation, so every other capability reads structured, cache-consistent service records
instead of parsing `host:port` strings out of a system discovery daemon.

## ADDED Requirements

### Requirement: Multicast browsing on IPv4 and IPv6

Discovery SHALL query the mDNS multicast destinations `224.0.0.251:5353` (IPv4) and `ff02::fb:5353`
(IPv6) and SHALL accept answers arriving on either family, so a responder reachable over only one
family is still discovered.

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

#### Scenario: Receiver on a non-default port

- **WHEN** a responder advertises its instance on SRV port 5000
- **THEN** the record's port is 5000 and a caller connecting to that record targets port 5000

### Requirement: Structured service records

Results SHALL be records exposing the service instance name, the service type, the SRV target
hostname, the resolved addresses, the SRV port, the decoded TXT map and the record TTL as separate
values, so reading a port never requires parsing a host string.

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

#### Scenario: Override is reported instead of the resolved address

- **WHEN** the advertised address is configured to a value that differs from the discovered address
- **THEN** the record's advertised address is the configured value while the socket's local address
  remains the discovered interface address

### Requirement: Bounded browse with observable outcomes

Browsing SHALL run for a caller-bounded window and SHALL return a result carrying the records found
and the reason it ended (data available, window elapsed, or cancelled). Finding no devices SHALL be a
result with no records and no raised error, never a timeout exception.

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

#### Scenario: Unusable interface

- **WHEN** a caller browses on an interface name that does not exist
- **THEN** the call raises the transport error with its documented code instead of returning an empty
  result

### Requirement: Enumeration and lookup

`Airplay.devices` SHALL enumerate the current records, lookups SHALL find a device by its advertised
display name and by its address or identifier, and discovering the same instance again SHALL NOT add
a duplicate entry.

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

#### Scenario: Sender sends only queries

- **WHEN** a caller browses while the harness responder records every packet it receives
- **THEN** all received packets are queries and none is a response or an unsolicited announcement

#### Scenario: Incoming query is not answered

- **WHEN** the harness responder sends a service query to the library's discovery socket
- **THEN** the library sends no response

