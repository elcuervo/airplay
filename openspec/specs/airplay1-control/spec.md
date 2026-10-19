# airplay1-control Specification

## Purpose

The legacy AirPlay 1 control plane: server information, photo display, URL playback, transport
commands, playback status and digest authentication against receivers that never implemented
AirPlay 2, driven from the modern async session.

## Requirements

### Requirement: Server information retrieval

The sender SHALL retrieve receiver information with `GET /server-info` and SHALL expose the decoded XML property list as a name-to-value map. Every key the receiver reports (`deviceid`, `model`, `srcvers`, `protovers`, `features` and any other) MUST be preserved with its reported value.

```ruby
info = session.server_info
info["model"]   # => "AppleTV3,2"
info["srcvers"] # => "220.68"
```

#### Scenario: Reading receiver information

- **WHEN** server information is requested from a receiver that answers `200` with a plist carrying `model`, `srcvers` and `features`
- **THEN** the returned map contains those three keys with the reported values

#### Scenario: Unrecognised keys are preserved

- **WHEN** the receiver reports a key the sender does not interpret
- **THEN** that key is present in the returned map with its reported value

### Requirement: Server information failures

When `GET /server-info` is answered with a status outside 2xx, or with a body that is not a property list, the sender MUST fail with a protocol-category error carrying the HTTP status and MUST NOT return a partially populated map.

```ruby
begin
  session.server_info
rescue Airplay::ProtocolError => error
  error.status # => 500, or nil for an unparsable body
end
```

#### Scenario: Receiver reports an error

- **WHEN** the receiver answers `GET /server-info` with `500`
- **THEN** the call fails with a protocol-category error carrying status 500 and no information map is returned

#### Scenario: Receiver answers with a non-plist body

- **WHEN** the receiver answers `200` with an HTML error page
- **THEN** the call fails with a protocol-category error and no information map is returned

### Requirement: Photo display

The sender SHALL display a picture with `PUT /photo`, sending the image bytes as the request body and their exact byte count in `Content-Length`. A `200` status means the picture was displayed; any other status MUST surface as a playback-category error carrying that status.

```ruby
session.photo(File.binread("photo.png"), transition: "Dissolve")
```

#### Scenario: Displaying a picture

- **WHEN** a 10240-byte JPEG is displayed on a receiver that records the request
- **THEN** the receiver records `PUT /photo`, a body of exactly 10240 bytes equal to the input, and a matching `Content-Length`, and the call reports success

#### Scenario: Receiver rejects the picture

- **WHEN** the receiver answers `PUT /photo` with `400`
- **THEN** the call fails with a playback-category error carrying status 400

### Requirement: Photo transitions

Every `PUT /photo` request SHALL carry an `X-Apple-Transition` header whose value is one of `None`, `Dissolve`, `SlideLeft` or `SlideRight`. Any other value MUST be rejected locally without issuing a request, and a request whose caller supplies no transition MUST send `None`.

```ruby
Airplay::Session::TRANSITIONS # => ["None", "Dissolve", "SlideLeft", "SlideRight"]
```

#### Scenario: Transition is sent

- **WHEN** a picture is displayed with the `Dissolve` transition
- **THEN** the receiver records `X-Apple-Transition: Dissolve`

#### Scenario: Unknown transition is refused locally

- **WHEN** a picture is displayed with the transition `Cube`
- **THEN** the call fails with a playback-category error and the receiver records no request

#### Scenario: Default transition

- **WHEN** a picture is displayed without a transition argument
- **THEN** the receiver records `X-Apple-Transition: None`

### Requirement: Photo payload integrity

Picture bytes SHALL reach the receiver unchanged. The sender MUST NOT transcode, re-encode, or change the encoding, line endings or byte count of a picture payload, whatever kind of input produced it.

```ruby
bytes = File.binread("photo.png") # sent verbatim, never transcoded
session.photo(bytes)
```

#### Scenario: Binary payload survives transport

- **WHEN** a picture whose bytes contain CRLF pairs and bytes above 0x7F is displayed
- **THEN** the digest the receiver computes over the received body equals the digest of the source bytes

#### Scenario: File bytes are sent verbatim

- **WHEN** a PNG file on disk is displayed
- **THEN** the received body is byte-identical to the file contents

### Requirement: Photo input kinds

The picture argument SHALL be accepted as a raw binary string, an existing readable file path, an object that responds to `read`, or an absolute URL, and each accepted kind MUST resolve to the bytes it denotes. Any other argument MUST fail with a playback-category error before any request is issued.

```ruby
session.photo("photo.png")          # path
session.photo(StringIO.new(bytes))  # object responding to read
session.photo("http://host/p.png")  # URL
session.photo(bytes)                # raw binary string
```

#### Scenario: Local file, IO and URL resolve to the same bytes

- **WHEN** the same image is passed as a file path, as a `File`-like object responding to `read`, and as a URL the receiver-side fixture serves
- **THEN** all three transmissions carry identical bytes

#### Scenario: Unsupported argument

- **WHEN** the picture argument is an `Integer`
- **THEN** the call fails with a playback-category error and no request reaches the receiver

#### Scenario: Unreachable photo URL

- **WHEN** the picture argument is a URL whose host refuses the connection
- **THEN** the call fails with a connection-category error and no request reaches the receiver

### Requirement: Playback start request

Playback of a media URL SHALL start with `POST /play` carrying `Content-Type: text/parameters` and a body holding one `Key: value` line per parameter, lines separated by CRLF and terminated by CRLF. The body MUST carry `Content-Location` (the media URL) and `Start-Position`.

```ruby
session.play("http://example.com/movie.mp4")
# POST /play, content-type text/parameters, Content-Location + Start-Position
```

#### Scenario: Playing a remote URL

- **WHEN** a remote video URL is played
- **THEN** the receiver records `POST /play` with `Content-Type: text/parameters` and a body whose `Content-Location` line is that URL

#### Scenario: Playing a local file

- **WHEN** a local video file is played
- **THEN** the `Content-Location` value is the media URL the sender published for that file, not a filesystem path

### Requirement: Start position scale

`Start-Position` SHALL be a decimal fraction between `0.0` and `1.0` inclusive expressing the position relative to the media duration. A value outside that range MUST be rejected locally with a playback-category error and no request MUST be issued. The default is `0.0`.

```ruby
session.play("http://example.com/movie.mp4", position: 0.5)
```

#### Scenario: Resuming from the middle

- **WHEN** playback starts with initial position `0.5`
- **THEN** the receiver records `Start-Position: 0.5` and the body carries no other parameter than `Content-Location`

#### Scenario: Out-of-range start position

- **WHEN** playback starts with initial position `1.5`
- **THEN** the call fails with a playback-category error and the receiver records no request

### Requirement: Playback rate control

Pause and resume SHALL be expressed as `POST /rate?value=0` and `POST /rate?value=1` respectively. Any other playback rate MUST be sent as the caller's decimal value in the `value` query parameter.

```ruby
session.rate(0) # POST /rate?value=0
session.rate(1) # POST /rate?value=1
session.rate(2) # POST /rate?value=2
```

#### Scenario: Pausing and resuming

- **WHEN** playback is paused and then resumed
- **THEN** the receiver records `POST /rate?value=0` followed by `POST /rate?value=1`

#### Scenario: Non-unit playback rate

- **WHEN** playback is requested at rate `2`
- **THEN** the receiver records `POST /rate?value=2`

### Requirement: Playback stop

Playback SHALL be stopped with `POST /stop`. A non-200 answer MUST surface as a playback-category error carrying the status. Stopping a session where nothing is playing MUST still issue the request and MUST NOT fail locally.

```ruby
session.stop # POST /stop
```

#### Scenario: Stopping playback

- **WHEN** a playing session is stopped against a receiver that answers `200`
- **THEN** the receiver records `POST /stop` and the session reports a stopped state

#### Scenario: Stopping an idle session

- **WHEN** `stop` is called on a session that never started playback
- **THEN** the receiver records `POST /stop` and no error is reported

#### Scenario: Receiver refuses the stop

- **WHEN** the receiver answers `POST /stop` with `500`
- **THEN** the call fails with a playback-category error carrying status 500

### Requirement: Seek to position

Seeking SHALL be expressed as `POST /scrub?position=<seconds>` with the position as absolute seconds in the media timeline, sent as a decimal number. A negative position MUST be rejected locally with a playback-category error and no request MUST be issued.

```ruby
session.scrub(20.097) # POST /scrub?position=20.097
```

#### Scenario: Seeking forward

- **WHEN** the session seeks to `20.097` seconds
- **THEN** the receiver records `POST /scrub?position=20.097`

#### Scenario: Negative seek

- **WHEN** the session seeks to `-1` seconds
- **THEN** the call fails with a playback-category error and the receiver records no request

### Requirement: Playback property update

Playback properties SHALL be set with `PUT /setProperty?<name>`, where the property name is the only query argument and `Content-Type` is `application/x-apple-binary-plist`. The request body MUST be a binary property list carrying the supplied value; for the time-valued properties `forwardEndTime` and `reverseEndTime` the body carries the documented `epoch`, `flags`, `timescale` and `value` fields.

```ruby
session.set_property("forwardEndTime",
  "epoch" => 0, "flags" => 0, "timescale" => 1000, "value" => 5000)
```

#### Scenario: Setting the forward end time

- **WHEN** the forward end time is set on a playing session
- **THEN** the receiver records `PUT /setProperty?forwardEndTime` with `Content-Type: application/x-apple-binary-plist` and a body that decodes as a property list whose value carries `epoch`, `flags`, `timescale` and `value`

#### Scenario: Receiver reports a property error

- **WHEN** the receiver answers a property update with a body whose `errorCode` is `7`
- **THEN** the call fails with a playback-category error carrying error code 7

### Requirement: Playback information read

Playback information SHALL be read with `GET /playback-info` and exposed as a snapshot carrying `duration`, `position`, `rate`, `readyToPlay`, the buffering flags and the loaded and seekable time ranges as the receiver reports them. Time ranges MUST be exposed as start and duration pairs in seconds.

```ruby
snapshot = session.playback_info
[snapshot.duration, snapshot.position, snapshot.rate, snapshot.seekable]
```

#### Scenario: Reading a full playback snapshot

- **WHEN** the receiver answers with a plist carrying `duration`, `position`, `rate` and one seekable range
- **THEN** the snapshot exposes each of those values, with the range exposed as its start and duration

#### Scenario: Unparsable playback information

- **WHEN** the receiver answers `GET /playback-info` with `200` and a body that is not a property list
- **THEN** the call fails with a protocol-category error and no snapshot is returned

### Requirement: Playback information key presence

Keys the receiver does not report MUST remain absent from the snapshot instead of receiving fabricated defaults. An empty playback-info document means nothing is playing: the snapshot reports a stopped state with no duration, position or rate.

```ruby
session.playback_info.duration # => nil when the receiver omits it
session.playback_info.stopped? # => true for an empty document
```

#### Scenario: Receiver reports only the rate

- **WHEN** the receiver answers with a plist containing only `rate: 1`
- **THEN** the snapshot reports a playing state and exposes no duration

#### Scenario: Empty playback information

- **WHEN** the receiver answers with an empty plist dictionary
- **THEN** the snapshot reports a stopped state with no duration, position or rate

### Requirement: Scrub read

The current playback position SHALL be read with `GET /scrub`, whose body is a `text/parameters` document carrying `duration` and `position` in seconds as `name: value` lines. Both values MUST be exposed, and a body that does not carry that shape MUST fail with a protocol-category error.

```ruby
values = session.scrub # GET /scrub
[values["duration"], values["position"]]
```

#### Scenario: Reading position and duration

- **WHEN** the receiver answers `GET /scrub` with `duration: 83.124794` and `position: 14.467000`
- **THEN** the call exposes duration `83.124794` and position `14.467`

#### Scenario: Malformed scrub body

- **WHEN** the receiver answers `GET /scrub` with a body that carries no `name: value` line pairs
- **THEN** the call fails with a protocol-category error

### Requirement: Session identity headers

Every control request SHALL carry `User-Agent: MediaControl/1.0`, `X-Apple-Session-ID` and `X-Apple-Device-ID`, alongside the headers that the individual command defines.

```ruby
session.server_info
# every request carries User-Agent: MediaControl/1.0, X-Apple-Session-ID, X-Apple-Device-ID
```

#### Scenario: Headers on every command

- **WHEN** a session issues `GET /server-info`, `PUT /photo` and `POST /play` in sequence
- **THEN** the receiver records all three requests carrying the documented user agent and both session headers

### Requirement: Session identity stability

Session identifiers SHALL stay stable for the lifetime of a session: every request in one session MUST carry the same `X-Apple-Session-ID` and `X-Apple-Device-ID` values, the device identifier MUST be `0x` followed by twelve hexadecimal digits, and two sessions MUST NOT share either value.

```ruby
Airplay::Session.open(device) { |session| session.server_info }
# identifiers stay fixed for the session and differ between sessions
```

#### Scenario: One session, several commands

- **WHEN** a session issues three commands
- **THEN** all three requests carry identical session and device identifiers

#### Scenario: Distinct sessions

- **WHEN** two sessions target the same receiver
- **THEN** the two sessions use different `X-Apple-Session-ID` and `X-Apple-Device-ID` values

### Requirement: Control connection reuse

The control plane SHALL hold one HTTP/1.1 connection per session and reuse it across successive commands. When the receiver closes the connection the sender MUST re-establish it transparently for the next command, and it MUST close the connection when the session closes.

```ruby
Airplay::Session.open(device) do |session|
  session.server_info
  session.playback_info
  session.stop
end
```

#### Scenario: Sequential commands share a connection

- **WHEN** a session issues three commands in sequence against a keep-alive receiver
- **THEN** the receiver accepts one TCP connection for all three

#### Scenario: Reconnect after a peer close

- **WHEN** the receiver closes the connection after the first response and a second command follows
- **THEN** the second command succeeds on a newly established connection

#### Scenario: Session close releases the connection

- **WHEN** the session is closed
- **THEN** the receiver observes the connection closed

### Requirement: Digest challenge response

When a receiver answers `401` with a `WWW-Authenticate: Digest` challenge, the sender SHALL replay the same request once with an RFC 2617 `Authorization: Digest` header computed with MD5 over the configured password, the challenged realm and nonce, and the request's own method and target. When the challenge offers `qop=auth`, the replay MUST carry `qop`, `nc` and `cnonce`.

```ruby
session = Airplay::Session.new(device, password: "hunter2")
session.server_info # 401 Digest challenge, then one signed replay
```

#### Scenario: Answering a digest challenge

- **WHEN** the receiver challenges `POST /play` with digest and accepts a correctly computed response
- **THEN** the receiver records exactly two requests, the second carrying `Authorization: Digest` with the challenged realm and nonce and a body identical to the first

#### Scenario: Challenge offering qop

- **WHEN** the challenge carries `qop="auth"`
- **THEN** the replay carries `qop=auth`, `nc=00000001` and a client nonce

#### Scenario: Non-digest challenge

- **WHEN** the receiver answers `401` with a `WWW-Authenticate` scheme other than `Digest`
- **THEN** the call fails with an authentication-category error and the sender does not replay the request

### Requirement: Digest username selection

The digest username SHALL be `iTunes` when the challenged realm is `raop` and `Airplay` otherwise, and the realm and nonce MUST come from the challenge rather than from constants. A username configured on the session MUST take precedence over this selection.

```ruby
Airplay::Session.new(device, password: "pw")                    # iTunes for raop, Airplay otherwise
Airplay::Session.new(device, password: "pw", digest_username: "Custom")
```

#### Scenario: RAOP realm

- **WHEN** the challenge carries `realm="raop"`
- **THEN** the replayed request carries `username="iTunes"`

#### Scenario: AirPlay realm

- **WHEN** the challenge carries `realm="AirPlay"` and no username is configured
- **THEN** the replayed request carries `username="Airplay"`

#### Scenario: Configured username override

- **WHEN** the session is configured with an explicit digest username
- **THEN** the replayed request carries that username whatever realm the challenge names

### Requirement: Password required versus password wrong

A `401` answer MUST be reported as `auth_required` when the session holds no password for the device, and as `auth_failed` when a password is configured and the signed replay is refused. Both MUST carry the machine-readable code and the HTTP status, and both MUST leave the session usable for a later retry.

```ruby
rescue Airplay::AuthRequiredError => e; e.code # => :auth_required, status 401
rescue Airplay::AuthFailedError   => e; e.code # => :auth_failed, status 401
```

#### Scenario: Password required

- **WHEN** a passwordless session receives `401`
- **THEN** the call fails with code `auth_required`, status 401, and the receiver records a single request

#### Scenario: Password wrong

- **WHEN** a session with a configured password receives `401` for the challenge and `401` again for the signed replay
- **THEN** the call fails with code `auth_failed`, status 401, and the receiver records exactly two requests

#### Scenario: Retry after supplying the password

- **WHEN** a session that failed with `auth_required` is given the correct password and the command is retried
- **THEN** the retried command succeeds against a receiver that accepts the digest response

### Requirement: Credential secrecy in logs

The sender MUST NOT write a device password, a digest response, or the contents of an `Authorization` header into logs, error messages or progress output.

```ruby
# no password, Authorization value or digest response is logged
session = Airplay::Session.new(device(password: "hunter2"))
```

#### Scenario: Failing authentication writes no secret

- **WHEN** a session with the password `hunter2` fails authentication and the session's log output is captured
- **THEN** no captured line contains the password or a digest response value

### Requirement: Explicit device origin

A session SHALL be able to target a receiver given as an explicit base URL, with no discovery step: every control request MUST be addressed to that host and port, and the base URL's path component MUST be joined with each command path so that a trailing slash never produces a doubled separator.

```ruby
session = Airplay::Session.new(device, base_url: "http://192.0.2.10:7000/prefix/")
session.server_info # => GET /prefix/server-info
```

#### Scenario: Explicit origin

- **WHEN** a session is opened with the base URL `http://192.0.2.10:7000/`
- **THEN** every recorded request targets host `192.0.2.10`, port 7000, and paths such as `/server-info`

#### Scenario: No discovery for an explicit origin

- **WHEN** a session is opened with an explicit base URL
- **THEN** no mDNS browse is performed for that session

### Requirement: Device error surfacing

Every control answer outside 2xx SHALL surface as a typed error carrying the HTTP status and its taxonomy category, and a failing playback command MUST NOT be reported as success. The sender MUST NOT replay a failing playback command automatically, beyond the digest challenge replay.

```ruby
begin
  session.play("http://example.com/x")
rescue Airplay::PlaybackError => error
  error.status # => 500; the command is never replayed
end
```

#### Scenario: Failing play command

- **WHEN** the receiver answers `POST /play` with `500`
- **THEN** the call fails with a playback-category error carrying status 500 and the receiver records exactly one `POST /play`

#### Scenario: Failing scrub read

- **WHEN** the receiver answers `GET /scrub` with `404`
- **THEN** the read fails with a protocol-category error carrying status 404

### Requirement: Legacy route selection

The legacy control plane SHALL be used only when the session's route decision selects it or when the caller requests it explicitly. When the device's advertised capabilities include AirPlay 2 the legacy plane MUST NOT be selected by default, and a failing legacy command MUST NOT cause an automatic switch to the modern path.

```ruby
Airplay::Session.new(device, capabilities: capabilities)            # refuses AirPlay 2 devices
Airplay::Session.new(device, capabilities: capabilities, legacy: true) # forces the legacy plane
```

#### Scenario: Modern device without an override

- **WHEN** a session is opened against a device whose advertised capabilities include AirPlay 2 and no override is requested
- **THEN** the session's route is not the legacy plane and the receiver records no legacy control request

#### Scenario: Forcing the legacy plane

- **WHEN** the caller requests the legacy route explicitly for a device that advertises AirPlay 2
- **THEN** the legacy control requests are issued against that device

#### Scenario: No automatic cross-route fallback

- **WHEN** `POST /play` fails with `500` on a legacy session
- **THEN** the failure is surfaced and no modern-path request is issued
