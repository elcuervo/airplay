# async-runtime Specification

## Purpose
One reactor and one structured task tree per process give the library deterministic, cancellable
concurrency for timing-sensitive AirPlay I/O, replacing the thread-per-actor model that cannot
express anchored playback or multi-room starts.

## Requirements

### Requirement: Single reactor session lifecycle

The library SHALL run one Async reactor per process and SHALL expose each device interaction as a
session created through `Airplay::Session.open(device) { |session| ... }`, which SHALL close every
socket, task and timer it opened before returning to the caller.

```ruby
device = Airplay::Device.new(name: "Apple TV", host: "192.168.1.12", port: 7000)

Airplay::Session.open(device) do |session|
  response = session.get("/server-info")
  puts response.status
end
```

#### Scenario: Session releases its resources

- **WHEN** a session block finishes after connecting and issuing a command
- **THEN** no socket, task or timer created by that session remains after `open` returns

#### Scenario: Concurrent sessions progress together

- **WHEN** two sessions against two devices are open at the same time
- **THEN** each may have a request in flight while the other is awaiting a response

### Requirement: Bounded operations and cancellation

Every network operation SHALL be bounded by a timeout, and cancelling or failing a session SHALL
cancel its child tasks and close their sockets instead of leaving them running.

```ruby
Airplay::Session.open(device, timeout: 0.5) do |session|
  session.get("/server-info") # raises Airplay::TimeoutError when the receiver stalls
end
```

```ruby
session = Airplay::Session.new(device)
session.spawn { loop { sleep 0.1 } }
session.cancel # child task stopped, client closed
```

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

```ruby
begin
  Airplay.open(device) { |session| session.get("/server-info") }
rescue Airplay::TimeoutError => error
  warn "#{error.code}: #{error.message}" # timeout: GET /server-info timed out after 5.0s
rescue Airplay::TransportError => error
  warn "#{error.code}: #{error.message}" # connection_refused: connection refused by ...
rescue Airplay::AuthRequiredError, Airplay::AuthFailedError => error
  warn "#{error.code}: #{error.message}" # auth_required / auth_failed
end
```

#### Scenario: Unreachable device

- **WHEN** a session targets a device whose port refuses connections
- **THEN** the raised error is the transport error type and carries its documented code

#### Scenario: Authentication failure is distinguishable

- **WHEN** a device rejects a request that carried credentials
- **THEN** the raised error is the authentication error type and is distinguishable from a request that carried none

### Requirement: Non-blocking reactor

Name resolution and other potentially blocking calls SHALL be performed without stalling the
reactor, so a slow operation in one session SHALL NOT delay progress in another.

```ruby
Airplay.sync do |task|
  slow = task.async do
    Airplay::Session.open(slow_device) { |session| session.get("/server-info") }
  end

  Airplay::Session.open(fast_device) { |session| session.get("/server-info") }
  slow.stop
end
```

#### Scenario: Slow resolution does not block a peer

- **WHEN** one session is resolving a hostname that takes seconds to answer
- **THEN** a concurrent session completes its request during that window

### Requirement: Structured status reporting

Session lifecycle and playback status SHALL be emitted as structured events with stable field names,
so a user interface can consume them without parsing human-readable text.

```ruby
Airplay.configure do |config|
  config.log_level = :debug
  config.output = $stdout
end

Airplay::Status.emit("playback.progress", position: 4, duration: 10)
# {"severity":"info","subject":"playback.progress","position":4,"duration":10,...}
```

#### Scenario: Status events carry fields

- **WHEN** a playback session reports progress
- **THEN** the emitted event exposes its values as named fields rather than only as a formatted line

#### Scenario: Verbosity is configurable

- **WHEN** the configured log level is raised to debug
- **THEN** debug events are emitted, and at the default level they are not

### Requirement: Configuration without removed language APIs

Process-scoped configuration SHALL be settable for log level, discovery and the advertised address,
and SHALL load without raising on the supported Ruby versions.

```ruby
Airplay.configure do |config|
  config.log_level = :debug
  config.autodiscover = true
  config.advertised_address = "192.168.1.20"
  config.timeout = 2
end

Airplay.reset_configuration!
```

#### Scenario: Configure then run

- **WHEN** a caller sets the log level and then runs a device command
- **THEN** the command completes and the configured verbosity is applied
