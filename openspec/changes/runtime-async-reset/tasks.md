# Tasks

## 1. Toolchain and development environment

- [ ] 1.1 Add `flake.nix` declaring the default dev shell (primary Ruby lane, bundler, OpenSSL
      bindings, `pkg-config`, `jq`, git), the compatibility Ruby lane, and the integration shell with
      `ffmpeg`, `avahi`, `shairport-sync`, `owntone`, `uxplay`; commit `flake.lock`; verify
      `nix develop -c ruby -v`, `nix develop -c bundle -v` and `nix develop .#integration -c ffmpeg -version` all succeed
- [ ] 1.2 Configure isolated gem state inside the shell (`GEM_HOME` and `BUNDLE_PATH` under the
      project or the flake's own store) and verify `nix develop -c bundle install` succeeds while the
      host's broken global `openssl` and `json` gems remain installed
- [ ] 1.3 Add the lane definitions to `Rakefile` (`test:unit`, `test:protocol`, `test:hardware`,
      `test:all`, with `default` = unit + protocol) and verify `nix develop -c rake` passes and
      `rake test:hardware` reports skips rather than failures with no hardware configured
- [ ] 1.4 Replace `.travis.yml` with a CI workflow that runs the lanes through the flake on both
      Ruby lanes, and verify the workflow runs green on the change branch before anything else lands
- [ ] 1.5 Document the environment, lanes and contributor setup in `doc/`, regenerate `README.md` via
      `rake doc:generate`, and verify the documented commands run as written

## 2. Dependency surgery and clean cutover

- [ ] 2.1 Rewrite both gemspecs and `Gemfile` (`required_ruby_version`, runtime set `async`,
      `async-http`, `console`, `plist`, `mime-types`; development set minitest 5 and a
      mock HTTP library) and verify `bundle install` and `bundle exec ruby -Ilib -e 'require "airplay"'` succeed
- [ ] 2.2 Remove celluloid, reel, reel-rack, cuba, net-ptth, log4r, micromachine, fakeweb, vcr and
      minitest-given from the code and manifests, and verify no `require` or constant from those gems
      remains anywhere under `lib/`, `bin/` or `test/`
- [ ] 2.3 Remove the language APIs that no longer exist (`Fixnum`, `File.exists?`, taint-era calls)
      and verify a load test plus a grep over `lib/` show none remaining
- [ ] 2.4 Confirm no tracked file references the removed gems or Ruby 2.x requirements, and verify
      `git grep -nE 'celluloid|net-ptth|log4r|micromachine|dnssd|reel|fakeweb'` returns nothing under
      `lib/` and `test/`

## 3. Session facade and error taxonomy

- [ ] 3.1 Implement `Airplay::Session` with `open(device)` block semantics, child-task ownership and
      close-on-exit, and verify a unit test asserts no sockets, tasks or timers survive the block
- [ ] 3.2 Implement operation timeouts and session cancellation, and verify tests cover a device that
      accepts then stalls (bounded failure) and a cancel during in-flight work (traffic stops, sockets close)
- [ ] 3.3 Implement the typed error taxonomy with stable codes for transport, protocol,
      authentication, playback and timing failures and verify each type and code is asserted by a unit test
- [ ] 3.4 Add a reactor-safety test proving a multi-second name resolution in one session does not
      delay a request in another, and a containment test proving a raising session leaves a peer running
- [ ] 3.5 Provide the synchronous facade for one-shot commands on top of the session and verify a
      test drives the same scenario through both paths with equal results

## 4. Configuration, logging and status reporting

- [ ] 4.1 Replace the old configuration/log loading with process-scoped configuration (log level,
      discovery, advertised address) that does not touch removed APIs and verify `Airplay.configure`
      followed by a command works and restores defaults between tests
- [ ] 4.2 Emit session and playback status as structured `console` events with stable field names,
      and verify a test asserts field presence and level filtering at default and debug verbosity
- [ ] 4.3 Provide progress rendering for human output built from those events and verify it degrades
      to structured-only output when output is not a terminal

## 5. Test harness skeleton

- [ ] 5.1 Add the dev-only fake-device package (separate gemspec, excluded from the runtime gems)
      exposing a `start`/`stop` lifecycle and a recorded-exchanges accessor, and verify it installs in
      the dev shell and is absent from both runtime gemspecs' file lists
- [ ] 5.2 Implement the virtual receiver's lifecycle (start and stop on a loopback port), its
      configurable service record (name, port, model, capability mask) and its recorded-exchange
      accessor, and verify the smoke scenario connects to it at that address and reads back the
      configured record with no avahi installed; the multicast responder that advertises it is
      delivered by the `mdns-discovery` change, which consumes this lifecycle
- [ ] 5.3 Implement per-test fault configuration (delay, drop, truncate, reset, error status,
      authentication challenge, corrupted tag) and verify one test per fault observes the sender's
      documented failure path
- [ ] 5.4 Add the injectable clock and verify a timing assertion completes without wall-clock sleeps
- [ ] 5.5 Add the opt-in hardware lane with environment-gated configuration, recording device model
      and version, and verify it skips cleanly with nothing configured
- [ ] 5.6 Port the existing unit expectations that still describe real behavior and delete those that
      only pinned the old implementation's wording, verifying `rake test:unit` covers the session,
      configuration and harness surfaces

## 6. Integration check

- [ ] 6.1 Run the full default lane in both Ruby lanes and verify green, then run the library load
      check and the CLI entry point against a non-existent device to verify the documented error path
- [ ] 6.2 Verify the five sibling changes can each read the facade and harness contracts they depend
      on: their proposals reference `Airplay::Session`, the error taxonomy, the lanes and the virtual
      receiver by the names established here

## Workflow follow-up

- Archive this change before any sibling change starts; the siblings consume its facade and harness.
- After archive, re-read the archived spec for `test-harness` before extending it with protocol modes.
