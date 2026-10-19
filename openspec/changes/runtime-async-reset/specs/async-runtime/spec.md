# Spec Delta

## Purpose

One reactor and one structured task tree per process give the library deterministic, cancellable
concurrency for timing-sensitive AirPlay I/O, replacing the thread-per-actor model that cannot
express anchored playback or multi-room starts.

## ADDED Requirements

### Requirement: Single reactor session lifecycle

The library SHALL run one Async reactor per process and SHALL expose each device interaction as a
session created through `Airplay::Session.open(device) { |session| ... }`, which SHALL close every
socket, task and timer it opened before returning to the caller.

#### Scenario: Session releases its resources

- **WHEN** a session block finishes after connecting and issuing a command
- **THEN** no socket, task or timer created by that session remains after `open` returns

#### Scenario: Concurrent sessions progress together

- **WHEN** two sessions against two devices are open at the same time
- **THEN** each may have a request in flight while the other is awaiting a response

### Requirement: Bounded operations and cancellation

Every network operation SHALL be bounded by a timeout, and cancelling or failing a session SHALL
cancel its child tasks and close their sockets instead of leaving them running.

#### Scenario: Device accepts then stalls

- **WHEN** a device accepts the connection and never sends a response
- **THEN** the operation fails with a timeout error within the configured bound and the session is closed

#### Scenario: Cancellation stops traffic

- **WHEN** a caller cancels a session during playback
- **THEN** outbound traffic for that session stops and its sockets are closed

### Requirement: Typed error taxonomy

Failures SHALL be raised as typed errors carrying a stable machine-readable code, distinguishing at
least transport, protocol, authentication, playback and timing failures, so callers never match on
message text.

#### Scenario: Unreachable device

- **WHEN** a session targets a device whose port refuses connections
- **THEN** the raised error is the transport error type and carries its documented code

#### Scenario: Authentication failure is distinguishable

- **WHEN** a device rejects a request that carried credentials
- **THEN** the raised error is the authentication error type and is distinguishable from a request that carried none

### Requirement: Non-blocking reactor

Name resolution and other potentially blocking calls SHALL be performed without stalling the
reactor, so a slow operation in one session SHALL NOT delay progress in another.

#### Scenario: Slow resolution does not block a peer

- **WHEN** one session is resolving a hostname that takes seconds to answer
- **THEN** a concurrent session completes its request during that window

### Requirement: Structured status reporting

Session lifecycle and playback status SHALL be emitted as structured events with stable field names,
so a user interface can consume them without parsing human-readable text.

#### Scenario: Status events carry fields

- **WHEN** a playback session reports progress
- **THEN** the emitted event exposes its values as named fields rather than only as a formatted line

#### Scenario: Verbosity is configurable

- **WHEN** the configured log level is raised to debug
- **THEN** debug events are emitted, and at the default level they are not

### Requirement: Configuration without removed language APIs

Process-scoped configuration SHALL be settable for log level, discovery and the advertised address,
and SHALL load without raising on the supported Ruby versions.

#### Scenario: Configure then run

- **WHEN** a caller sets the log level and then runs a device command
- **THEN** the command completes and the configured verbosity is applied
