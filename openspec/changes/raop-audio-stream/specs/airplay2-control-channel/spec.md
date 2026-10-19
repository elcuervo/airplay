# Spec Delta

## ADDED Requirements

### Requirement: Audio Stream Setup Extends The Authenticated Session

Both audio setup phases MUST ride the session's existing authenticated control connection as binary property lists, and MUST NOT open a second control connection. A session whose audio setup fails MUST keep its control channel usable, so a retry is possible on the same session.

#### Scenario: Phases ride the paired channel

- **WHEN** an audio stream is set up on a paired session
- **THEN** the phase-one request and the phase-two stream definition are exchange frames on the already-paired connection, and no additional control connection is opened

#### Scenario: Failure leaves the channel usable

- **WHEN** the stream definition is rejected
- **THEN** the audio binding reports a coded error and a following request on the same control session still succeeds

### Requirement: Audio Stream Key Exchange Is Per Session

The audio stream key MUST be generated per session, MUST be 32 bytes, and MUST be carried in the phase-two stream definition. It MUST NOT be written to logs or persisted with the session's credentials, and it MUST be forgotten when the session tears down.

#### Scenario: A fresh key per session

- **WHEN** two sessions are set up to the same receiver
- **THEN** each stream definition carries its own 32-byte key and the two keys differ

#### Scenario: The key never reaches persistent state

- **WHEN** a session is set up and torn down
- **THEN** the emitted logs and the credential store contain no value equal to the stream key

### Requirement: Audio Stream Type Is Recorded On The Session

The session MUST record the negotiated stream type after phase two — realtime or buffered — together with its payload type, and MUST expose both to callers. The audio transport MUST use the recorded values.

#### Scenario: A buffered negotiation is recorded

- **WHEN** the receiver advertises buffered audio and the route selects it
- **THEN** the session reports the recorded stream type as buffered with the buffered payload type

#### Scenario: A realtime negotiation is recorded

- **WHEN** the route selects realtime audio
- **THEN** the session reports the recorded stream type as realtime with the realtime payload type

### Requirement: Audio Stream Lifecycle Commands Ride The Authenticated Session

Record, flush, buffered flush and teardown MUST be sent on the authenticated session channel, carrying the session identifier the receiver issued. Each non-success response MUST surface as a coded error naming the command and MUST NOT be treated as success.

#### Scenario: Lifecycle commands carry the session identifier

- **WHEN** any lifecycle command is sent
- **THEN** the request carries the session identifier returned by the receiver's setup

#### Scenario: A rejected flush is reported

- **WHEN** the receiver rejects a flush command
- **THEN** the caller receives a coded playback error naming the flush, and the session does not report the flush as applied

#### Scenario: A rejected teardown is reported

- **WHEN** the receiver rejects or does not answer a teardown command
- **THEN** the caller receives a coded error naming the teardown while the local session resources are still released

### Requirement: Audio Stream Serves Reverse Transport Events

While an audio stream is playing, transport commands received on the session's reverse event channel MUST be applied to the stream within one feedback interval and MUST be reflected in the state the session reports to callers.

#### Scenario: A remote pause stops content

- **WHEN** a pause command arrives on the event channel while content is playing
- **THEN** content delivery stops within one feedback interval and the session reports its state as paused

#### Scenario: A remote stop closes the stream

- **WHEN** a stop command arrives on the event channel
- **THEN** content delivery stops, the stream is torn down, and the session reports its state as stopped

#### Scenario: Unknown events do not disturb playback

- **WHEN** an event the sender does not implement arrives
- **THEN** playback continues and the event is reported as unhandled
