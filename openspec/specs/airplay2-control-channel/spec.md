# airplay2-control-channel Specification

## Purpose

Defines the authenticated AirPlay 2 control plane carried on a paired connection: capability discovery from the receiver, session setup with identity and timing negotiation, the reverse event channel, the periodic feedback keepalive, parameter delivery and orderly teardown.

## Requirements

### Requirement: Info response decoding

The sender SHALL request `GET /info` on every newly paired control connection and decode the response as a binary property list; a response that is not a decodable binary property list MUST fail the session with `connect_failed` rather than be interpreted as capabilities.

```ruby
session = Airplay::Control::Session.new(connection, timing_port: 7001).establish
session.info["deviceid"]
```

#### Scenario: A binary plist info response is decoded

- **WHEN** a virtual receiver answers `GET /info` with a binary property list
- **THEN** the sender decodes it and the session continues

#### Scenario: A non-plist info response fails the session

- **WHEN** the receiver answers `GET /info` with a body that is not a binary property list
- **THEN** the session fails with `connect_failed` and no capabilities are taken from the body

### Requirement: Info feeds the capability model

The sender SHALL pass the capability payload of the decoded `GET /info` response into the device capability model so that the rest of the session reads authoritative capabilities rather than only discovered ones.

```ruby
session.capabilities.source(:mask) # => :authoritative
session.capabilities.mask
```

#### Scenario: One info request updates the model

- **WHEN** a session is established with a virtual receiver
- **THEN** exactly one `GET /info` request is issued on that connection and the capability model reflects the response's payload afterwards

### Requirement: Session setup request

`POST /setup` SHALL carry a binary property list containing the sender's device identity, a session UUID, a group UUID, the timing protocol the sender requests and the port the sender's timing responder listens on.

```ruby
session.timing_protocol # => "NTP"
session.timing_port     # => 7010
```

#### Scenario: Setup carries identity, identifiers and timing

- **WHEN** a session is set up against a virtual receiver
- **THEN** the decoded request body contains the sender identity, a session UUID and a group UUID, the requested timing protocol and a non-zero timing port

### Requirement: Session identity uniqueness

The sender MUST generate a fresh session UUID and group UUID for every session and MUST NOT reuse either identifier for a different session on the same device.

```ruby
session.session_id # => a fresh UUID per session
session.group_id   # => a fresh UUID per session
```

#### Scenario: Two sessions get four distinct identifiers

- **WHEN** two sessions are opened against the same device in sequence
- **THEN** the session and group UUIDs of the second differ from those of the first

### Requirement: Timing protocol negotiation

The sender SHALL record the timing protocol the receiver confirms in the SETUP response and MUST fail the session with a timing error when the receiver confirms no timing protocol the sender implements, rather than continuing without timing agreement.

```ruby
session.timing_protocol # => "NTP"; a PTP-only response raises :timing_error
```

#### Scenario: A confirmed protocol is recorded

- **WHEN** the receiver's SETUP response confirms NTP timing
- **THEN** the session records NTP as the negotiated timing protocol and the timing port from the response

#### Scenario: An unimplemented protocol fails the session

- **WHEN** the receiver's SETUP response confirms only a timing protocol the sender does not implement
- **THEN** the session fails with a timing error and no stream is started

### Requirement: Reverse event channel

The sender SHALL accept the receiver's connection back to the event port advertised in SETUP, decrypt that connection's frames and surface each decoded event property list to the session for as long as the session lasts.

```ruby
session.events               # => [{"type"=>"playing"}]
session.event_channel_lost?  # => false while connected
```

#### Scenario: An event arrives on the reverse channel

- **WHEN** a virtual receiver connects to the advertised event port and sends a playback state event as an encrypted frame
- **THEN** the sender surfaces the decoded event to the session

#### Scenario: Loss of the event channel does not silently continue

- **WHEN** the receiver closes the event connection
- **THEN** the session records the event channel as gone and surfaces it, instead of treating the session as healthy

### Requirement: Feedback keepalive

While a session is active, the sender SHALL post `POST /feedback` at the interval the receiver requires, carrying the current stream and playback state, and MUST stop sending feedback once the session ends.

```ruby
Airplay.clock.advance(session.feedback_interval)
session.tick # => true, one POST /feedback
```

#### Scenario: Feedback is emitted at the required interval

- **WHEN** the injectable clock advances by the receiver-required interval during an active session
- **THEN** exactly one `POST /feedback` with the current state is sent for that interval

#### Scenario: A missing feedback cycle ends the session

- **WHEN** feedback is withheld beyond the interval the receiver requires
- **THEN** the virtual receiver tears the session down and the sender surfaces the termination rather than reporting the session as still active

### Requirement: Volume parameter curve

A volume change sent with `SET_PARAMETER` SHALL encode the sender's 0.0 to 1.0 volume linearly onto the −30 to 0 dB range, so 0.0 encodes as −30 dB, 0.5 as −15 dB and 1.0 as 0 dB.

```ruby
session.volume = 0.0 # SET_PARAMETER volume -30.0
session.volume = 0.5 # -15.0
session.volume = 1.0 # 0.0
```

#### Scenario: The curve is linear in decibels

- **WHEN** volumes of 0.0, 0.5 and 1.0 are sent
- **THEN** the decoded request bodies carry −30, −15 and 0 dB respectively

### Requirement: Metadata parameters

The sender SHALL send the active item's track metadata to the receiver with `SET_PARAMETER` so the receiver can render it, and MUST send the parameters again whenever the metadata changes.

```ruby
session.metadata = { "title" => "One", "artist" => "A", "album" => "B" }
```

#### Scenario: Metadata reaches the receiver

- **WHEN** the sender sets title, artist and album for the active item
- **THEN** the virtual receiver's most recently received parameters contain those three values

#### Scenario: A metadata change is re-sent

- **WHEN** the metadata for the active item changes during a session
- **THEN** a further `SET_PARAMETER` carrying the new values is sent

### Requirement: Session teardown

`POST /teardown` SHALL end the session: the sender closes the event channel, stops feedback, sends nothing further for that session and retires its session and group UUIDs.

```ruby
session.teardown
session.active? # => false; no further frame or feedback is sent
```

#### Scenario: Teardown releases everything

- **WHEN** a session is torn down
- **THEN** the event connection is closed, no further frame or feedback is sent for that session, and the retired UUIDs are not used for the next session

### Requirement: Unauthenticated control response

When the receiver answers a control request with `401`, the sender MUST surface `auth_required`, discard the connection and re-authenticate on a fresh connection, and MUST NOT repeat the request on the same connection.

```ruby
Airplay::Control::Session.open(device, store: store, timing_port: 7001)
# a 401 raises :auth_required and retries on a fresh connection
```

#### Scenario: A 401 triggers re-authentication on a new connection

- **WHEN** a virtual receiver answers the first control request of a session with `401`
- **THEN** the sender surfaces `auth_required`, opens a new connection, completes pairing there and does not resend the request on the original connection
