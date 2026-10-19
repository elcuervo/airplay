# Spec Delta

## Purpose

Turns a discovered device's advertised capabilities, access-control flags and stored credentials into the single route the sender drives it over — legacy AirPlay 1, RAOP-compat or AirPlay 2 native — together with the timing and stream-type hints the streaming paths consume.

## ADDED Requirements

### Requirement: Route decision inputs

The route decision SHALL be a pure function of the device's advertised 64-bit feature mask (AirPlay 2 bits 38 and 48, HK pairing bit 46, PTP bit 41, buffered-audio bit 40, video v2 bit 49, legacy video bits 0 and 1, audio bit 9), the advertised status flags (`flags`/`sf`, covering the PIN-required and legacy-pairing indications), the password flag (`pw`) and whether credentials are stored for the device.

#### Scenario: Routing needs no connection

- **WHEN** a device record carrying those fields is submitted to the route decision
- **THEN** a route is returned without any network request being made

#### Scenario: Unrelated bits do not change the outcome

- **WHEN** the same device record is submitted twice, once with an extra unrelated feature bit set
- **THEN** both submissions return the same route

### Requirement: AirPlay 2 native route

A device that advertises an AirPlay 2 feature bit (38 or 48) together with the HK pairing bit (46), and for which credentials are stored, SHALL be routed to AirPlay 2 native.

#### Scenario: A paired modern receiver routes to AirPlay 2

- **WHEN** a device advertises bits 38 and 46 and a credential record exists for it
- **THEN** the returned route is AirPlay 2 native with no pairing step in the session plan

### Requirement: Pairing route for unpaired devices

A device that advertises the AirPlay 2 feature bits and HK pairing but for which no credentials are stored SHALL be routed to AirPlay 2 native with the session plan beginning at pair-setup.

#### Scenario: An unpaired modern receiver still routes to AirPlay 2

- **WHEN** a device advertises bits 38 and 46 and no credential record exists for it
- **THEN** the returned route is AirPlay 2 native and the session plan names pair-setup as its first step

### Requirement: Password-protected devices

A device whose advertised password flag is set SHALL require a password before pairing, and a session started without one MUST fail with `auth_required` without sending any pairing material.

#### Scenario: A missing password is reported before any exchange

- **WHEN** a device advertising the password flag is routed without a configured password
- **THEN** the session fails with `auth_required` and the virtual receiver records no pairing request

### Requirement: Advertised status flags

The route decision SHALL treat the advertised status flags as authoritative indications: a device indicating that pairing requires a PIN SHALL be routed to a flow that supplies one before any control request, and a device indicating legacy pairing only SHALL be routed to the legacy authentication path rather than the AirPlay 2 pairing flow.

#### Scenario: A PIN-required device is never reached unauthenticated

- **WHEN** a device whose status flags indicate PIN-required pairing is routed
- **THEN** the session plan supplies the PIN before its first control request and no control request is sent first

#### Scenario: A legacy-pairing-only device is not sent the modern pairing flow

- **WHEN** a device whose status flags indicate legacy pairing only is routed
- **THEN** the session plan uses the legacy route's authentication and issues no pair-setup request

### Requirement: Legacy AirPlay 1 route

A device that advertises no AirPlay 2 feature bit and does advertise a legacy video feature bit SHALL be routed to legacy AirPlay 1.

#### Scenario: An AirPlay 1 receiver keeps the legacy route

- **WHEN** a device advertises the legacy video capability and the audio capability but neither AirPlay 2 bit
- **THEN** the returned route is legacy AirPlay 1

### Requirement: RAOP-compat route

A device resolved through `_raop._tcp` that advertises no AirPlay 2 feature bit and no legacy video capability SHALL be routed to RAOP-compat.

#### Scenario: An audio-only receiver routes to RAOP compat

- **WHEN** a device discovered through `_raop._tcp` advertises the audio capability only
- **THEN** the returned route is RAOP-compat

### Requirement: Timing and stream-type hints

The route decision SHALL record, alongside the route, the timing mode taken from bit 41, the stream type taken from bit 40 and the video flavour taken from bit 49, for the streaming paths that own those behaviours.

#### Scenario: Hints follow the advertised bits

- **WHEN** a device with bits 41 and 40 set is routed, and then the same device without those bits is routed
- **THEN** the first decision records PTP timing and buffered streaming while the second records NTP timing and realtime streaming

#### Scenario: Video flavour is carried as a hint

- **WHEN** a device advertising the video v2 bit is routed
- **THEN** the decision records the video v2 flavour for the video path without itself performing any video negotiation

### Requirement: Explicit route override

A caller-supplied override SHALL select the route directly, skipping the capability table, and the decision SHALL record that the route came from an override rather than from capabilities.

#### Scenario: An override wins over the table

- **WHEN** a caller requests the legacy AirPlay 1 route for a device that would otherwise route to AirPlay 2 native
- **THEN** the returned route is legacy AirPlay 1 and the decision records the override as its source

### Requirement: Route feasibility

A route selected by override that the device cannot support MUST fail with `unsupported_feature` naming the route, and MUST NOT be silently substituted by a different route.

#### Scenario: An impossible override is rejected

- **WHEN** a caller overrides a device that lacks the HK pairing bit to the AirPlay 2 native route
- **THEN** the decision fails with `unsupported_feature` naming AirPlay 2 native

### Requirement: Route is fixed for the session

Once a session has started, its route MUST NOT change; a failure on the chosen route MUST surface the corresponding error rather than being retried on another route within the same session.

#### Scenario: A failed AirPlay 2 session does not fall back silently

- **WHEN** a session routed to AirPlay 2 native fails during pairing
- **THEN** the failure is surfaced and no legacy request is issued on that session
