# Spec Delta

## ADDED Requirements

### Requirement: Timing Mode Selection Is Limited To What The Session Can Establish

The route MUST select a timing mode the sender can actually serve. A receiver that advertises PTP MUST still be timed through the NTP responder until a PTP engine is bound and answering, and a session MUST NOT advertise a timing protocol it cannot serve. The effective timing mode MUST be recorded on the session and reported to callers, including when it differs from what the receiver advertised.

#### Scenario: Advertised PTP falls back to NTP

- **WHEN** the receiver advertises PTP but the sender has no PTP engine bound
- **THEN** the session negotiates the NTP timing protocol, advertises our timing responder's port, and records that the advertised mode could not be established

#### Scenario: The effective mode is what is served

- **WHEN** a session has fallen back to NTP
- **THEN** the clock exchange it serves is the NTP responder and the reported effective mode is NTP, not the advertised PTP

#### Scenario: No protocol is advertised that cannot be served

- **WHEN** the phase-one timing negotiation is prepared
- **THEN** the advertised timing protocol names a mode the session has a bound responder for

### Requirement: Timing Stream Type Selection Requires An Established Timing Route

Buffered audio MUST be selected only when the receiver advertises buffered-audio support and the session's timing route is established, meaning a bound timing source whose timeline the buffered anchor can express. Otherwise the route MUST select realtime audio, even for a receiver that advertises buffered audio.

#### Scenario: Buffered audio on an unestablished route falls back to realtime

- **WHEN** the receiver advertises buffered audio and the session's timing mode is the NTP responder, with no established PTP timeline
- **THEN** the route selects realtime audio and the session records why buffered was not selected

#### Scenario: Buffered audio on an established route

- **WHEN** the receiver advertises buffered audio and the session holds an established timing route that can express the buffered anchor
- **THEN** the route selects buffered audio with its buffered payload type

#### Scenario: A receiver without buffered audio is never given a buffered stream

- **WHEN** the receiver does not advertise buffered-audio support
- **THEN** the route selects realtime audio regardless of the timing route

### Requirement: Timing And Stream Type Are Decided Before Stream Setup

The timing mode and stream type MUST be decided and recorded on the session before the audio stream definition is sent, and the stream definition MUST declare exactly the recorded values. A mismatch between the recorded decision and the declared stream definition MUST be treated as a protocol error rather than sent as-is.

#### Scenario: The decision exists before the stream definition

- **WHEN** the audio stream definition is sent
- **THEN** the session already reports its timing mode and stream type

#### Scenario: The declaration matches the decision

- **WHEN** the stream definition's payload type is compared with the recorded stream type
- **THEN** they agree, and a constructed mismatch is refused before the request leaves the sender
