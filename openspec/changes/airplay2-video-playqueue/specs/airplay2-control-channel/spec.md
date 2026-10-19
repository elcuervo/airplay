# Spec Delta

## ADDED Requirements

### Requirement: URL Control Stream registration

The session MUST be able to request a URL control stream with a session `SETUP` whose stream entry is
of type 130 and carries the client UUID, the remote-control client type, the channel identifier and a
control type of 1, and it MUST expose the stream identifier the receiver returns for that stream.

#### Scenario: Registered

- **WHEN** the session requests a URL control stream and the receiver returns a stream identifier
- **THEN** that identifier is readable by the caller and the request matched the profile's recorded shape

#### Scenario: Not registered

- **WHEN** the receiver's answer carries no stream entry with a stream identifier
- **THEN** the session raises the protocol failure for the control stream instead of exposing a default identifier

### Requirement: URL Control Stream command requests

The session MUST expose a command request to `POST /command` whose body is an Apple binary plist
wrapping a nested binary plist payload and which carries the session identifier and the URL control
stream identifier.

#### Scenario: Command request shape

- **WHEN** a caller sends a command on the URL control stream
- **THEN** the recorded request shows the wrapped binary-plist body and both identifiers, and the nested payload decodes to the caller's command

### Requirement: URL Control Stream responses are data

The status of a command response MUST be returned to the caller as data without raising, so a caller
can classify a transient `500`, an authentication status and any other non-2xx itself.

#### Scenario: Non-2xx returned

- **WHEN** the receiver answers `POST /command` with `500`
- **THEN** the caller receives that status and the session raises nothing

### Requirement: URL Control Stream event delivery

Events pushed on the encrypted event channel MUST be decoded — including a message whose payload is a
binary plist nested inside the plist's data member — and delivered to the session's listeners, and
every event request MUST be acknowledged with a successful response.

#### Scenario: Event decoded and acknowledged

- **WHEN** the receiver pushes a playback-state event, nested or not
- **THEN** the listener receives the decoded event and the receiver double observes a successful acknowledgement for that request

#### Scenario: A message that is not an event

- **WHEN** an event-channel message carries no decodable plist payload
- **THEN** it is ignored without raising and the channel stays open

### Requirement: URL Control Stream response correlation

The session MUST correlate answers that arrive on the event channel carrying a response kind and a
message identifier with the request that used that identifier, and MUST ignore answers whose
identifier matches no outstanding request.

#### Scenario: Correlated response

- **WHEN** a request that used a message identifier is answered on the event channel with the same identifier
- **THEN** that answer is delivered to the waiting caller and to no other caller

#### Scenario: Unmatched response

- **WHEN** an answer arrives whose identifier matches no waiting request
- **THEN** it is dropped without raising

### Requirement: URL Control Stream is distinct from the MediaRemote channel

The URL control stream MUST be requested with a control type and a client type that differ from the
values used for the receiver's MediaRemote data channel, and MUST NOT be satisfied by that channel.

#### Scenario: Distinct request values

- **WHEN** the session requests the URL control stream
- **THEN** the receiver double observes control type 1 with the remote-control client type, while a request carrying the MediaRemote control type is handled as that channel instead

### Requirement: URL Control Stream setup ordering

The session MUST verify the pairing, read the receiver's information, establish the session, send the
record request and only then request the URL control stream, in that order, because a receiver drops
the connection when a later step is performed early.

#### Scenario: Order observed

- **WHEN** a modern-route session starts
- **THEN** the receiver double observes that order and no queue command before the URL control stream was registered

#### Scenario: A step performed early

- **WHEN** the receiver's information is read before pairing verification, or feedback starts before the record request
- **THEN** the receiver double drops the connection and the session reports the connection failure

### Requirement: URL Control Stream feedback exclusivity

Periodic feedback MUST NOT be in flight while a queue command is issued on the same connection,
because feedback is sequence-matched while the command requests are not, and an overlap makes
receivers drop the connection.

#### Scenario: No overlap

- **WHEN** a queue command is issued after feedback has started
- **THEN** the receiver double observes no outstanding feedback request at the moment the command arrives

### Requirement: URL Control Stream channel identity

The channel identifier and the client identifiers of the URL control stream MUST be derived from the
identity the profile selects for the receiver rather than being fixed values, so two sessions paired
with different receivers do not present the same identity.

#### Scenario: Derived, not fixed

- **WHEN** two sessions register a URL control stream against two receivers with different identities
- **THEN** the recorded channel identifiers differ and each carries the identity the profile selects
