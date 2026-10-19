## Usage

### CLI

```text
air help
air version
air list     # discovered devices
air doctor   # per-device type, host, port, addresses and capabilities
```

`air list` and `air doctor` browse the local network; `--interface` and `--window`
narrow the browse. Protocol verbs (`play`, `view`) are added by the protocol
changes that implement them.

### Library

#### Configuration

```ruby
Airplay.configure do |config|
  config.log_level         # :debug, :info, :warn, :error or :fatal (Default: :info)
  config.autodiscover      # Allows discovery to run for one-shot commands (Default: true)
  config.advertised_address # Address handed to receivers (Default: nil, chosen per interface)
  config.media_port        # Media server port; 0 picks an OS-assigned port (Default: 0)
  config.timeout           # Per-request timeout in seconds (Default: 5.0)
  config.digest_username   # Overrides the realm-derived digest username (Default: nil)
  config.output            # Structured event sink (Default: $stdout)
end
```

Configuration is process-scoped. `Airplay.reset_configuration!` restores the
defaults, which is what the test suite uses between cases.

#### Sessions

```ruby
require "airplay"

device = Airplay::Device.new(name: "Apple TV", host: "192.168.1.12", port: 7000)

Airplay::Session.open(device) do |session|
  response = session.get("/server-info")
  puts response.status
end
```

A session owns one HTTP client, every child task it starts and every socket it
opens. `Session.open` closes all of them before returning, including when the
block raises. Requests are bounded by `config.timeout` and failures raise
`Airplay::Error` subclasses carrying a stable `code`.

The synchronous facade runs the same block in the process reactor:

```ruby
Airplay.open(device) do |session|
  session.get("/server-info")
end
```

#### Legacy AirPlay 1

A session speaks the legacy control plane directly: one keep-alive HTTP/1.1
connection, `User-Agent: MediaControl/1.0`, a stable `X-Apple-Session-ID` and an
`X-Apple-Device-ID` per session. Every command maps onto that client:

```ruby
Airplay::Session.open(device, password: "hunter2") do |session|
  session.server_info                 # GET /server-info
  session.photo(picture, transition: "Dissolve") # PUT /photo
  session.play("http://host/movie.mp4", position: 0.5) # POST /play
  session.rate(0)                     # POST /rate?value=0
  session.scrub(20.097)               # POST /scrub?position=20.097
  session.stop                        # POST /stop
  session.playback_info               # GET /playback-info snapshot
  session.scrub                       # GET /scrub (duration and position)
end
```

Transitions are `None`, `Dissolve`, `SlideLeft` and `SlideRight`. A failing
command raises a typed error carrying the HTTP status; a `401` on a session
without a password raises `auth_required`, and a rejected signed replay raises
`auth_failed`.

Use `--url` to skip discovery and target a receiver directly:

```sh
air play http://host/movie.mp4 --url http://192.168.1.12:7000
air view photo.png --url http://192.168.1.12:7000 --transition SlideLeft
air view ./photos --url http://192.168.1.12:7000 --wait 5
```

A local file played through `air play` is published by the session's media
server, which serves byte ranges (`206`, `Content-Range`, `HEAD`) for the life
of the session and returns a stable, opaque URL. AirPlay 2 devices use the
modern route; pass `--legacy` (or `legacy: true` to the session) to force the
legacy plane.

#### AirPlay 2

This build opens the HomeKit-style pairing gate: transient and PIN pair-setup,
pair-verify, HKDF channel keys, ChaCha20-Poly1305 control framing, per-device
credentials outside the repository, the authenticated control plane (`GET /info`,
`POST /setup`, the reverse event channel, feedback, parameters, teardown) and a
capability-driven route decision.

Deferred: FairPlay, MFi, HAP accessory mode and PTP timing (NTP is used). A
receiver that demands FairPlay, MFi or HAP accessory mode fails with
`Airplay::UnsupportedError` (`:unsupported_feature`) naming the mechanism, and a
receiver that confirms only PTP fails with `Airplay::TimingError`
(`:timing_error`).

#### Status events

Lifecycle and playback status are emitted as structured fields, so a UI can
consume them without parsing text:

```ruby
Airplay::Status.emit("playback.progress", position: 4, duration: 10)
```

When the configured output is a terminal, `Airplay::Status.progress` renders a
progress bar; otherwise it returns `nil` and the structured events are the only
output.
