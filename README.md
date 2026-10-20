# Airplay

[![CI](https://github.com/elcuervo/airplay/actions/workflows/ci.yml/badge.svg)](https://github.com/elcuervo/airplay/actions/workflows/ci.yml)

![Airplay](doc/img/logo.png)

Airplay attempts to be compatible with the latest AppleTV firmware but I'd like
to add compatibility to other servers.

## Contribute

You can contribute with code, bugs or feature requests.

The development of the gem takes time and there's a lot of research and hardware
tests to make all of this. If you want to contribute please consider donating as
much as you want in: [Paypal](https://www.paypal.com/cgi-bin/webscr?cmd=_s-xclick&hosted_button_id=HE867B8J6ARQ4) or [Gumroad](https://gumroad.com/l/airplay)

# Table of Contents

* [Contribute](#contribute)
* [Installation](#installation)
* [Usage](#usage)
  * [CLI](#cli-1)
  * [Library](#library-1)
* [Discovery](#discovery)
* [Video play queue](#video-play-queue)
* [Development environment](#development-environment)
* [Testing](#testing)
* [Documentation](#documentation)
* [Contributors](#contributors)

## Installation

Ruby 4.0 or newer is required.

Discovery is pure Ruby and needs no system daemon or native extension.

### Library

`gem install airplay`

## CLI

`gem install airplay-cli`

## Usage

### CLI

```text
air help                      # usage, every action and every option
air version                   # CLI version
air list                      # discovered devices
air doctor                    # per-device type, host, port, addresses, capabilities
air play URL|FILE             # play on the selected device
air pause                     # pause the current playback
air resume                    # resume the current playback
air stop                      # stop the current playback
air seek SECONDS              # seek within the current item
air next                      # select the next queue item
air previous                  # select the previous queue item
air rate VALUE                # set the playback rate
air view PICTURE|FOLDER       # display a picture or a slideshow
```

`air list` and `air doctor` browse the local network; `--interface` and `--window`
narrow the browse. `play` reports the route it chose before it starts:

```text
route: queue (the receiver reports modern video control on firmware 870.14.1)
firmware: 870.14.1 profile: tvos-26.5
```

The same lines name the route for a legacy receiver and for a receiver whose
firmware is unknown (the conservative policy keeps it on the legacy route).

Options: `--device NAME`, `--url URL` (skip discovery), `--password PASS`,
`--legacy` (force the AirPlay 1 route), `--no-now-playing`, `--position SECONDS`,
`--wait [SECONDS]`, `--transition NAME`, `--interface NAME`, `--window SECONDS`,
`--interactive`, `--help` and `--version`.

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
  config.now_playing       # Push now-playing on the modern route (Default: true)
  config.conservative_route # Keep unknown firmware on the legacy route (Default: true)
  config.timing_port       # Local timing port advertised in SETUP (Default: 7001)
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

#### Selecting a route and playing

`Airplay::Player.open` decides the playback route from the capability model,
hands the media to it and exposes the transport verbs and the state model:

```ruby
Airplay::Player.open(device, capabilities: record.capabilities) do |player|
  player.play("http://host/movie.mp4", position: 5.0)
  puts player.decision.route       # :queue or :legacy
  puts player.state.status         # :unknown, :stopped, :loading, :playing, :paused
  player.wait { |state| puts state.position }
  player.pause
  player.resume
  player.seek(30.0)
  player.rate(2.0)
  player.next
  player.previous
  player.stop
end
```

The modern route additionally exposes `add`, `remove`, `request_snapshot` and
`now_playing` (the MediaRemote pushes). See `doc/protocol.md` for the wire
contract, the profile table and the error matrix.

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

## Discovery

Discovery is pure Ruby and runs on the process reactor. It browses multicast DNS for
`_airplay._tcp.local.` and `_raop._tcp.local.`, resolves `PTR -> SRV -> TXT -> A/AAAA`,
and returns structured records. The library never advertises, announces or answers a
service; it only sends queries and consumes answers.

### Browse

```ruby
results = Airplay.browse(window: 2.0)

results.reason  # => :data_available, :window_elapsed or :cancelled
results.records.each do |record|
  puts "#{record.display_name} #{record.host}:#{record.port}"
end
```

The port always comes from the SRV answer; discovery never assumes 7000. The record exposes
the instance name, display name, service type, SRV target, addresses with their interface,
TXT map, TTL and capability model as separate values.

```ruby
record = results.records.first
record.name          # => "Living Room"
record.display_name  # => "Living Room" (the part after "@" for RAOP)
record.identifier    # => "AA:BB:CC:DD:EE:FF" (RAOP identifier or TXT deviceid)
record.service_type  # => "_airplay._tcp.local."
record.target        # => "living-room.local."
record.port          # => 7000
record.addresses     # => [#<Address ip="192.0.2.10" family=:ipv4 interface="en0">]
record.txt           # => {"deviceid"=>"...", "features"=>"..."}
```

### Address selection

One instance answering on several interfaces yields one record carrying every address.
The preferred address is deterministic: an address on a receiving interface, IPv4 before
IPv6, link-local last. Link-local addresses keep their scope identifier (`fe80::1%en0`).

The advertised address can be overridden without changing the socket's local bind address:

```ruby
Airplay.configure { |config| config.advertised_address = "203.0.113.10" }
record.advertised_address # => "203.0.113.10"
```

### Capabilities

The TXT map is normalized into a capability model. Unknown keys and RAOP hints stay
readable in `record.txt`.

```ruby
capabilities = record.capabilities
capabilities.mask                 # => 0x0008030040000a00
capabilities.video?               # bit 0
capabilities.video_v2?            # bit 49
capabilities.photo?               # bit 1
capabilities.slideshow?           # bit 5
capabilities.screen?              # bit 7
capabilities.audio?               # bit 9
capabilities.unified_media_control? # bit 38
capabilities.pairing?             # bit 46
capabilities.transient_pairing?   # bit 43 or 48
capabilities.airplay2?            # bit 38 or 48
capabilities.buffered_audio?      # bit 40 and srcvers >= 354.54.6
capabilities.ptp?                 # bit 41 and srcvers >= 366
capabilities.password_required?   # pw=true or status bit 0x80
capabilities.pin_required?        # status bit 0x8
capabilities.legacy_pairing?      # status bit 0x200
capabilities.restricted_access?   # acl=1
```

Feature and gate values come from pyatv's `AirPlayFlags`, the openairplay
`airplay-spec`, and `lmcgartland/airplay2-rs` (`AIRPLAY_2_SPEC.md`). Where the references
disagree, the raw mask stays available and the model names only the agreed predicates.
A missing or malformed value is reported as unknown, never raised; a version gate with an
unknown `srcvers` reports unavailable.

A later authoritative source can replace the values it defines while the original TXT map
stays readable:

```ruby
live = record.capabilities.refresh("features" => "0x40000a00,0x80300", "srcvers" => "354.54.6")
live.source(:mask) # => :authoritative
live.txt["features"] # => the original TXT value
```

### Cache and bounded windows

Records are cached for the TTL of the answer that produced them. A browse inside the TTL
is served from the cache without sending a query; expiry re-queries; a TTL-0 goodbye
removes the instance. Browsing is always caller-bounded and never raises for an empty
network:

```ruby
result = Airplay.browse(window: 0.5)
result.records # => []
result.reason  # => :window_elapsed
```

An unusable interface is a different outcome and raises the runtime's transport error:

```ruby
begin
  Airplay::Discovery::Browser.new(interfaces: ["nope0"]).browse(window: 0.2)
rescue Airplay::TransportError => error
  error.code # => :interface_unavailable
end
```

### CLI

```sh
air list    # one line per discovered device
air doctor  # name, type, host, port, addresses, capabilities and TXT
```

`air list` prints nothing and exits 0 on an empty network. `air doctor` exits non-zero
when discovery fails with a typed error.

## Video play queue

The modern video route drives the receiver's own play queue over the
authenticated control channel. It is selected from the capability model, never
from a failed request; a receiver without `video_v2` control support, or one
whose firmware is unknown while `configuration.conservative_route` is in force,
stays on the legacy `POST /play` route.

The session log names the decision (`player.route` in `player.decision`) and the
profile selection (`queue.profile`), including the reason a default profile was
chosen.

### URL control stream registration

`POST /setup` carries one stream entry:

| Field         | Value                                      |
|---------------|--------------------------------------------|
| `type`        | `130`                                      |
| `controlType` | `1`                                        |
| `clientUUID`  | the sender's device identifier             |
| `clientType`  | the profile's remote-control client type   |
| `channelID`   | the channel identity the profile selects   |

The receiver answers with a `streams` array whose `type 130` entry carries the
`streamID`. Every queue command afterwards carries it in the profile's stream
header (`x-apple-stream-id` or `x-apple-streamid`). An answer without a
`streamID` raises `:control_stream` carrying the response status, and no queue
command is sent.

The channel identifier is derived, not fixed: profiles with receiver identity
use `/info`'s `deviceid` (or the receiver identity), profiles with sender
identity use the sender's device identifier, so two sessions paired with
different receivers do not present the same identity.

### Session ordering

1. pair-verify
2. `GET /info`
3. session `POST /setup` (identity and timing)
4. `POST /record`
5. URL control stream `POST /setup`
6. queue commands

Receivers drop the connection when a later step is performed early, and when a
feedback request is outstanding while a queue command is issued (feedback is
sequence-matched, commands are not). The sender therefore completes feedback
before issuing a command.

### Command envelope

Each queue command is a `POST /command` whose body is a binary plist:

```ruby
{ "command" => Airplay::Plist::Data.new(Airplay::Plist.dump("type" => name, "params" => params)) }
```

Headers carry `user-agent` (profile sender version), `x-apple-session-id` and the
profile's stream header. A bare body whose top level is the command itself is
refused by the receiver with a client error.

### Profiles

Wire values are profile data pinned by committed fixtures in
`test/fixtures/queue/`, each with its provenance.

| Profile     | Firmware   | Sender             | Stream header        | Channel identity | `actionAtItemEnd` |
|-------------|------------|--------------------|----------------------|------------------|-------------------|
| `tvos-26.5` | `870.14.1` | `AirPlay/870.14.1` | `x-apple-stream-id`  | receiver         | present           |
| `tvos-18.4` | `550.10`   | `AirPlay/550.10`   | `x-apple-stream-id`  | sender           | absent            |
| `default`   | unknown    | `AirPlay/960.13.1` | `x-apple-streamid`   | sender           | present           |

### Start sequence

`insertPlayQueueItem`, then `setProperty` `isInterestedInDateRange`, then
`setProperty` `actionAtItemEnd` when the profile includes it, then `setRate`.
The sequence stops at the first non-2xx response.

`insertPlayQueueItem` parameters:

| Field           | Meaning                                                     |
|-----------------|-------------------------------------------------------------|
| `uuid`          | the item identifier the sender uses for seek, select, remove |
| `url`           | the media URL handed to the receiver                         |
| `mediaType`     | the profile's media kind (`file`)                            |
| `secure`        | whether the URL is TLS-secured                               |
| `startPosition` | the requested start position, omitted when zero              |

A start position travels inside the item; it is never applied by a follow-up
seek. `setProperty` carries `name` and `value`.

For a local file the URL is an absolute URL on the address the receiver can
reach, served for the session's lifetime by the media server with the file's
content type, its length and byte ranges. When no reachable address exists the
play fails with `:unusable_media_address` instead of handing over a loopback URL.
A remote URL is passed through unchanged.

### Queue manipulation and transport

| Verb       | Queue command                                          |
|------------|--------------------------------------------------------|
| add        | `insertPlayQueueItem` (no start position)              |
| play       | `insertPlayQueueItem` with `startPosition`, then rate  |
| pause      | `setRate` with `rate` 0                                |
| resume     | `setRate` with `rate` 1                                |
| rate       | `setRate` with that value                              |
| stop       | `setRate` 0, then `removePlayQueueItem` for the item   |
| seek       | `seekToTime` with the item's `uuid` and `position`     |
| next       | `selectQueueItem` for the next item's `uuid`           |
| previous   | `selectQueueItem` for the previous item's `uuid`       |
| remove     | `removePlayQueueItem` for the item's `uuid`            |

No verb uses the legacy `/play`, `/rate` or `/scrub` endpoints on this route.
Stop leaves the session usable: a later play inserts a new item on the same
paired session.

### Playback state model

`Airplay::Playback::State` is route-independent. Each field is `nil` (unknown)
unless the receiver reported it:

| Field            | Source                                                    |
|------------------|-----------------------------------------------------------|
| `status`         | event `state`, or the polled answer's `rate`/emptiness    |
| `duration`       | event `duration`, or `GET /playback-info` `duration`      |
| `position`       | event `position`/`elapsed`, or `position`                 |
| `rate`           | event `rate`, or `rate`                                   |
| `ready_to_play`  | event `readyToPlay`, or `readyToPlay`                     |
| `stall_count`    | event `stallCount`, or `stallCount`                       |
| `item_id`        | event `uuid`/`itemID`, or `uuid`                          |
| `error_code`     | a reported `error.code` or `errorCode`                    |
| `error_domain`   | a reported `error.domain` or `errorDomain`                |

State comes from receiver reports only; an accepted command never means playing.
A play is started only after an observed `playing` state inside the startup
window; otherwise it fails with `:playback_not_started` and the poll/attempt
count is logged. `playing` followed by `loading` followed by `playing` is one
continuing playback; `stopped` after `playing` ends it. Each distinct change is
delivered once; a repeated report is not a change.

Events are decoded from the encrypted event channel, including a message whose
payload is a binary plist nested inside the `data` member, and every event
request is acknowledged. A message with no decodable payload is ignored and the
channel stays open.

When no event arrives, the sender polls `GET /playback-info` at a bounded
interval and logs the polled source. An empty answer means stopped, and a failing
`/playback-info` answer inside a queue session is not a playback failure. A
reported error object is surfaced with its code and domain.

A snapshot request (`getPlaybackState` with a `requestID`) is correlated by that
identifier: the answer updates the model once and an answer with an unknown
identifier is ignored.

### Now-playing

Four MediaRemote pushes on the encrypted control channel, in this order, once
per item: `updateNowPlayingInfo`, `updateSupportedCommands`,
`updatePlaybackState`, `updatePlaybackClient`. Pushes are serialized so two
changes never interleave.

`updateNowPlayingInfo` parameters: `nowPlayingInfo` with the `text` wrapper
(`title`, `artist`, `album`), `duration`, `elapsed`, `rate`, `timestamp` (a date
value), `uuid`, and for a retained artwork `artwork` bytes, `artworkMimeType`
and `artworkIdentifier`; plus `mergePolicy`.

Policy:

- change-driven only, never on a timer;
- a full push (`mergePolicy` `replace`) carries the artwork bytes again whenever
  artwork is retained, because receivers do not preserve it by identifier;
- a timeline correction (`mergePolicy` `update`) carries only timeline fields and
  no artwork; seek uses it, and pause/resume push the timeline before the state;
- stop pushes state only;
- the item `uuid` is stable across progress and fresh per item;
- an identical push is suppressed;
- a receiver that rejects the update form is downgraded to full pushes for the
  rest of the session.

Now-playing is only pushed on the queue route, can be disabled with
`configuration.now_playing = false` or `--no-now-playing`, and a rejected push is
recorded without failing the play.

### Retry and errors

Only the transient case is retried: the first queue command gets at most three
attempts, one second apart, and only when the receiver answers `500`. Nothing is
retried after the item insert, so a retried start cannot duplicate an item.

| Condition                                | Error                          | Code                    |
|------------------------------------------|--------------------------------|-------------------------|
| `401` on a queue command                 | `Airplay::AuthRequiredError`   | `:auth_required`        |
| `403` on a queue command                 | `Airplay::AuthFailedError`     | `:auth_failed`          |
| any other non-2xx command status         | `Airplay::ProtocolError`       | `:protocol_error`       |
| control stream refused or unregistered   | `Airplay::ProtocolError`       | `:control_stream`       |
| play accepted but never reported playing | `Airplay::PlaybackError`       | `:playback_not_started` |
| local media with no reachable address    | `Airplay::PlaybackError`       | `:unusable_media_address` |
| dropped connection                       | `Airplay::TransportError`      | `:connect_failed`       |
| connection refused                       | `Airplay::TransportError`      | `:connection_refused`   |

Every failure is emitted on the machine-readable status line (`code:` plus its
status when there is one) for both the library and the CLI.

### Findings

- The wire shape moved three times in 2026: `AirPlay/550.10`,
  `AirPlay/870.14.1` and `AirPlay/960.13.1`, with both `x-apple-stream-id` and
  `x-apple-streamid` spellings observed. The fixtures record one shape per
  firmware.
- The tvOS 26.5 branch validated with an NTP-timed session; one account reports
  events only on a PTP-timed video session. The hardware lane records the
  negotiated timing mode and the event count per scenario so a mode with no
  events is visible.
- Some receivers ignore now-playing without the MRP origin registration this
  change does not implement; the hardware lane records whether now-playing was
  pushed and leaves the rendering observation explicit.
- `GET /playback-info` errors inside a queue session; treating that error as a
  playback failure is what tore the picture down upstream. The lane records its
  status, and a successful answer is committed as a fixture with its provenance.

Fixtures: `test/fixtures/queue/<profile>.json` carries the commands and its
provenance (reference implementation and firmware), and
`test/fixtures/queue/insert.bplist` is the committed insert body.

## Development environment

The reference toolchain is pinned in `flake.nix` and `flake.lock`:

- Ruby 4.0.7, the latest stable release
- Bundler, OpenSSL bindings, `pkg-config`, `jq` and `git`

Enter it with `nix develop`. Gems resolve into `.nix/gems` through
`GEM_HOME`/`BUNDLE_PATH`, so the host's Ruby and global gem directory are never
used:

```sh
nix develop -c bundle install
nix develop -c bundle exec rake
```

The canonical development machine is macOS on Apple silicon. Continuous
integration is out of scope: the host is the reference environment.

### Without Nix

Ruby 4.0 with an isolated `BUNDLE_PATH` works:

```sh
bundle config set --local path .bundle/gems
bundle install
bundle exec rake
```

That path is supported but is not the reference environment.

# Testing

Tests are split into three lanes:

- `rake test:unit` — configuration, device model, error taxonomy, status events,
  the injectable clock, the DNS codec and the capability model. No sockets, no
  reactor.
- `rake test:protocol` — the in-process virtual receiver and mDNS responder
  double (`airplay-fake-device`) driving sessions and discovery over loopback:
  request recording, timeouts, cancellation, reactor safety, cache expiry,
  goodbyes and fault injection. The receiver also runs a legacy mode (scripted
  `server-info`, `photo`, `play`, transport, `playback-info` and `setProperty`
  responses), a digest-challenge mode with configurable realm, nonce, `qop` and
  credentials, photo-integrity assertions over the received body, and the
  connection knobs (close after response, delayed bodies). The same receiver has
  a play-queue mode: it registers the `type 130` control stream, answers
  `POST /command` with recorded nested payloads, keeps expectation lists that
  fail at the first divergence, pushes scripted event-channel transitions,
  answers `playback-info` from a script, offers the route's fault knobs and can
  fetch a media URL it was handed. No Apple TV, system daemon or external network
  required.
- The media server's byte-range contract is driven through a raw range client
  (`test/support/range_client.rb`), with 200/206/416/HEAD fixtures.
- `rake test:hardware` — opt-in validation against a real receiver. Set
  `AIRPLAY_HARDWARE_HOST` (and optionally `AIRPLAY_HARDWARE_PORT`) to run it;
  without them every test skips and the lane succeeds. The same lane exercises
  the legacy control plane and photo display against a legacy device; it records
  the model, firmware and outcome. The video scenarios read
  `AIRPLAY_HARDWARE_HLS_URL`, `AIRPLAY_HARDWARE_LOCAL_HLS` and
  `AIRPLAY_HARDWARE_LOCAL_FILE`, record the route, timing mode, profile, state
  sequence and event count per run, compare the modern and forced legacy routes,
  and commit a successful `playback-info` answer as a fixture with provenance.

`rake` runs unit and protocol. `rake test:all` runs all three.

Set `AIRPLAY_LIVE_DISCOVERY=1` to add the opt-in live-network browse check to the
protocol lane; it skips otherwise.

The virtual receiver and the mDNS responder are dev-only: they are absent from
both runtime gemspecs and are never loaded by the library.

## Documentation

All the documentation of the README can be found in the `doc` folder.
To generate an updated README based on the contents of `doc` please use `rake doc:generate`

## Contributors

Last but not least a special thanks to all the [contributors](https://github.com/elcuervo/airplay/graphs/contributors)

