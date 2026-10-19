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
  connection knobs (close after response, delayed bodies). No Apple TV, system
  daemon or external network required.
- The media server's byte-range contract is driven through a raw range client
  (`test/support/range_client.rb`), with 200/206/416/HEAD fixtures.
- `rake test:hardware` — opt-in validation against a real receiver. Set
  `AIRPLAY_HARDWARE_HOST` (and optionally `AIRPLAY_HARDWARE_PORT`) to run it;
  without them every test skips and the lane succeeds. The same lane exercises
  the legacy control plane and photo display against a legacy device; it records
  the model, firmware and outcome.

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

