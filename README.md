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
* [Development environment](#development-environment)
* [Testing](#testing)
* [Documentation](#documentation)
* [Contributors](#contributors)

## Installation

Ruby 4.0 or newer is required.

### Library

`gem install airplay`

## CLI

`gem install airplay-cli`

## Usage

### CLI

```text
air help
air version
```

Protocol verbs (`list`, `play`, `view`, `doctor`) are added by the protocol
changes that implement them.

### Library

#### Configuration

```ruby
Airplay.configure do |config|
  config.log_level         # :debug, :info, :warn, :error or :fatal (Default: :info)
  config.autodiscover      # Allows discovery to run for one-shot commands (Default: true)
  config.advertised_address # Address handed to receivers (Default: nil, chosen per interface)
  config.timeout           # Per-request timeout in seconds (Default: 5.0)
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

#### Status events

Lifecycle and playback status are emitted as structured fields, so a UI can
consume them without parsing text:

```ruby
Airplay::Status.emit("playback.progress", position: 4, duration: 10)
```

When the configured output is a terminal, `Airplay::Status.progress` renders a
progress bar; otherwise it returns `nil` and the structured events are the only
output.

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

The canonical development machine is macOS on Apple silicon. Linux is the CI
system and runs the same commands inside the flake.

### Integration shell

`nix develop .#integration` adds the optional simulators nixpkgs provides for the
platform: `ffmpeg`, `avahi` and `uxplay` on macOS, plus `shairport-sync` and
`owntone` on Linux. None of them is a runtime dependency of the library.

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

- `rake test:unit` — configuration, device model, error taxonomy, status events
  and the injectable clock. No sockets, no reactor.
- `rake test:protocol` — the in-process virtual receiver (`airplay-fake-device`)
  driving sessions over loopback: request recording, timeouts, cancellation,
  reactor safety and fault injection. No Apple TV, avahi or ffmpeg required.
- `rake test:hardware` — opt-in validation against a real receiver. Set
  `AIRPLAY_HARDWARE_HOST` (and optionally `AIRPLAY_HARDWARE_PORT`) to run it;
  without them every test skips and the lane succeeds.

`rake` runs unit and protocol. `rake test:all` runs all three.

The virtual receiver is a dev-only package: it is absent from both runtime
gemspecs and is never loaded by the library.

## Documentation

All the documentation of the README can be found in the `doc` folder.
To generate an updated README based on the contents of `doc` please use `rake doc:generate`

## Contributors

Last but not least a special thanks to all the [contributors](https://github.com/elcuervo/airplay/graphs/contributors)

