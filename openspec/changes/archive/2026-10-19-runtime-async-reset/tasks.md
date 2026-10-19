# Tasks

## 1. Toolchain and development environment

- [x] 1.1 Add `flake.nix` declaring the default dev shell on the canonical macOS arm64 host
      (Ruby 4.0.7, bundler, OpenSSL bindings, `pkg-config`, `jq`, git); commit `flake.lock`;
      verify `nix develop -c ruby -v`, `nix develop -c bundle -v` and `nix flake check` succeed
- [x] 1.2 Configure isolated gem state inside the shell (`GEM_HOME` and `BUNDLE_PATH` under the
      project or the flake's own store) and verify `nix develop -c bundle install` succeeds while
      the host's system Ruby remains untouched
- [x] 1.3 Add the lane definitions to `Rakefile` (`test:unit`, `test:protocol`, `test:hardware`,
      `test:all`, with `default` = unit + protocol) and verify `nix develop -c bundle exec rake`
      passes and `bundle exec rake test:hardware` reports skips rather than failures with no
      hardware configured
- [x] 1.4 Remove `.travis.yml`. No CI workflow is added in this change; verify the lane commands
      run green locally through `nix develop` before anything else lands
- [x] 1.5 Document the environment, lanes and contributor setup in `doc/`, regenerate `README.md` via
      `rake doc:generate`, and verify the documented commands run as written

## 2. Dependency surgery and clean cutover

- [x] 2.1 Rewrite both gemspecs and `Gemfile` (`required_ruby_version`, runtime set `async`,
      `async-http`, `console`; development set minitest 5) and verify `bundle install` and
      `bundle exec ruby -Ilib -e 'require "airplay"'` succeed
- [x] 2.2 Remove celluloid, reel, reel-rack, cuba, net-ptth, log4r, micromachine, fakeweb, vcr and
      minitest-given from the code and manifests, and verify no `require` or constant from those gems
      remains anywhere under `lib/`, `bin/` or `test/`
- [x] 2.3 Remove the language APIs that no longer exist (`Fixnum`, `File.exists?`, taint-era calls)
      and verify a load test plus a grep over `lib/` show none remaining
- [x] 2.4 Confirm no tracked file references the removed gems or Ruby 2.x requirements, and verify
      `git grep -nE 'celluloid|net-ptth|log4r|micromachine|dnssd|reel|fakeweb'` returns nothing under
      `lib/` and `test/`

## 3. Session facade and error taxonomy

- [x] 3.1 Implement `Airplay::Session` with `open(device)` block semantics, child-task ownership and
      close-on-exit, and verify a unit test asserts no sockets, tasks or timers survive the block
- [x] 3.2 Implement operation timeouts and session cancellation, and verify tests cover a device that
      accepts then stalls (bounded failure) and a cancel during in-flight work (traffic stops, sockets close)
- [x] 3.3 Implement the typed error taxonomy with stable codes for transport, protocol,
      authentication, playback and timing failures and verify each type and code is asserted by a unit test
- [x] 3.4 Add a reactor-safety test proving a multi-second name resolution in one session does not
      delay a request in another, and a containment test proving a raising session leaves a peer running
- [x] 3.5 Provide the synchronous facade for one-shot commands on top of the session and verify a
      test drives the same scenario through both paths with equal results

## 4. Configuration, logging and status reporting

- [x] 4.1 Replace the old configuration/log loading with process-scoped configuration (log level,
      discovery, advertised address) that does not touch removed APIs and verify `Airplay.configure`
      followed by a command works and restores defaults between tests
- [x] 4.2 Emit session and playback status as structured `console` events with stable field names,
      and verify a test asserts field presence and level filtering at default and debug verbosity
- [x] 4.3 Provide progress rendering for human output built from those events and verify it degrades
      to structured-only output when output is not a terminal

## 5. Test harness skeleton

- [x] 5.1 Add the dev-only fake-device package (separate gemspec, excluded from the runtime gems)
      exposing a `start`/`stop` lifecycle and a recorded-exchanges accessor, and verify it installs in
      the dev shell and is absent from both runtime gemspecs' file lists
- [x] 5.2 Implement the virtual receiver's lifecycle (start and stop on a loopback port), its
      configurable service record (name, port, model, capability mask) and its recorded-exchange
      accessor, and verify the smoke scenario connects to it at that address and reads back the
      configured record without any external service; the multicast responder that advertises it is
      delivered by the `mdns-discovery` change, which consumes this lifecycle
- [x] 5.3 Implement per-test fault configuration (delay, drop, truncate, reset, error status,
      authentication challenge, corrupted payload bytes) and verify one test per fault observes the
      sender's documented failure path; the corrupted-authentication-tag knob is added with the
      pairing mode, which first parses tags
- [x] 5.4 Add the injectable clock and verify a timing assertion completes without wall-clock sleeps
- [x] 5.5 Add the opt-in hardware lane with environment-gated configuration, recording device model
      and version, and verify it skips cleanly with nothing configured
- [x] 5.6 Port the existing unit expectations that still describe real behavior and delete those that
      only pinned the old implementation's wording, verifying `rake test:unit` covers configuration,
      errors, status and clock, and `rake test:protocol` covers the session and harness surfaces

## 6. Integration check

- [x] 6.1 Run the full default lane on the pinned Ruby lane and verify green, then run the library
      load check and the CLI entry point (`air help`, `air version`); the unreachable-device path
      is covered by the transport-error scenario
- [x] 6.2 Verify the five sibling changes can each read the facade and harness contracts they depend
      on: their proposals reference `Airplay::Session`, the error taxonomy, the lanes and the virtual
      receiver by the names established here

## Workflow follow-up

- Archive this change before any sibling change starts; the siblings consume its facade and harness.
- After archive, re-read the archived spec for `test-harness` before extending it with protocol modes.
