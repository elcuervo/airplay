# Proposal

## Why

The library cannot run on any supported Ruby. Its own code uses APIs that were removed from
the language — `Fixnum` (`lib/airplay/configuration.rb`), `File.exists?`
(`device.rb`, `viewer.rb`, `player/media.rb`), and the taint-era `Object#taint` that its
thread stack depends on; all three are absent on Ruby 3.4.9 (verified on this host), where
`require "airplay"` fails. Every gem behind the runtime is likewise unmaintained: celluloid
(0.17.0 pinned here, 2015; last release 0.18.0 in 2018), reel/reel-rack (2016), net-ptth
0.0.17 (2014), log4r 1.1.10 (2015), cuba 3.1, fakeweb 1.3.0 (2014), vcr 2.4, minitest 4.4.
There is also no reproducible toolchain: this host's global gem set is broken in two
independent ways — a user-installed `openssl-4.0.2` gem whose extension needs a missing
`libssl.so.3`, and a `json-2.21.1` extension linked against `libruby-3.4.8` while the
interpreter is 3.4.9. Nothing else in the revival can be built, run or tested until the
runtime, the dependency set and the development environment are replaced together.

## What Changes

- **BREAKING**: target Ruby ≥ 3.4 (4.0.7 is current stable) and replace the thread/actor
  concurrency model with an async-first core: one `Async` reactor per process, a session task
  tree with structured cancellation and timeouts. The public API becomes
  `Airplay::Session.open(device) { |session| ... }`; the old synchronous surface
  (`Airplay.devices`, `device.play`, `device.view`) survives only as a convenience wrapper for
  one-shot commands, and `device.play` now returns a session handle rather than a Celluloid
  actor.
- **BREAKING**: delete the dead stack — celluloid, reel, reel-rack, cuba, net-ptth, log4r,
  micromachine, fakeweb, vcr, minitest-given — and adopt `async ~> 2.46`, `async-http`,
  `console` (already an `async` runtime dependency), `plist`, and minitest 5. Discovery encodes and
  decodes DNS messages with the standard library's `Resolv::DNS::Message`, so no separate DNS
  dependency is added.
  `mime-types` and `net-http-digest-auth` (or a small in-repo replacement) stay.
- Add the project's development environment as a **`flake.nix` + `flake.lock`** pinned to
  nixpkgs, so every dependency for every part of this plan is declared and reproducible:
  - default dev shell: `ruby_4_0` plus `ruby_3_4` for the compatibility lane, `bundler`,
    `libssl`/`openssl`, `pkg-config`, `jq`, `git`;
  - isolated gem state per project (`GEM_HOME`/`BUNDLE_PATH` inside the shell) so the host's
    broken global gems can never shadow the project's;
  - a second shell (and/or `nix build` outputs) carrying the optional integration and
    simulator packages confirmed present in nixpkgs: `ffmpeg`, `avahi`, `shairport-sync`,
    `owntone`, `uxplay`;
  - `nix flake check` and CI that runs the test lanes inside `nix develop`, replacing
    `.travis.yml` (which still targets Ruby 2.0/2.1).
- Replace log4r with structured `console` logging and progress reporting driven from the
  reactor.
- Introduce an error taxonomy (connection, protocol, authentication, playback, timing) with
  machine-readable codes, so later protocol changes can fail loudly instead of silently.
- Stand up the test harness skeleton every later change extends: minitest 5 lanes
  (`test:unit`, `test:protocol` in-process virtual receiver, opt-in `test:hardware`),
  injectable clock, and the `airplay-fake-device` dev-only package boundary.
- Explicitly not in this change: no protocol behavior is added or changed, no CLI/TUI
  redesign, no new endpoints. This change is the floor the other five stand on.

## Capabilities

### New Capabilities
- `async-runtime`: one reactor per process, session task tree with structured cancellation and
  timeouts, error taxonomy with machine-readable codes, and structured logging/progress.
- `development-environment`: a flake-pinned, reproducible toolchain (Ruby versions, isolated
  gem state, optional integration packages), the test lanes, and CI parity with the dev shell.
- `test-harness`: the in-process virtual receiver and its conformance tiers (unit, protocol
  vectors, virtual receiver, capture replay, opt-in hardware) that validate each part of the
  system without physical AirPlay hardware.

### Modified Capabilities
- None. `openspec/specs/` is empty; this change introduces the first capabilities.

## Impact

- Deletes the Celluloid/Reel/Cuba/log4r stack and its configuration surface
  (`Airplay::Configuration#load`, `Airplay::Logger`, `Airplay::Server`'s rack boot) and
  rewrites `lib/airplay.rb` and every `require` in `lib/`.
- Both gemspecs (`required_ruby_version`, dependencies), `Gemfile`, `Gemfile.lock`, `Rakefile`
  lanes, `test/test_helper.rb` and `test/integration_helper.rb` (the `TEST_TV_URL` helper that
  needs a real Apple TV), and the removal of `.travis.yml`.
- Adds `flake.nix`, `flake.lock`, a dev-only fake-device package, and a CI configuration that
  consumes the flake.
- `mdns-discovery`, `airplay1-legacy-sender`, `airplay2-pairing-control`,
  `airplay2-video-playqueue` and `raop-audio-stream` all depend on the session facade, the
  error taxonomy, the plist/crypto baseline and the harness introduced here.
