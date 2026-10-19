# Spec Delta

## Purpose

A flake-pinned toolchain with isolated gem state makes every dependency of this plan reproducible,
on a host whose global Ruby gems are already broken in two independent ways.

## ADDED Requirements

### Requirement: Flake-defined toolchain

The repository SHALL declare its toolchain in `flake.nix` with a committed `flake.lock`, so that
`nix develop` provides Ruby, bundler, OpenSSL bindings, `pkg-config`, `jq` and git without relying
on the host's global package set.

#### Scenario: Fresh shell has the toolchain

- **WHEN** `nix develop` is entered in a fresh checkout
- **THEN** `ruby -v`, `bundle -v` and `openssl version` all succeed inside that shell

#### Scenario: Flake evaluates cleanly

- **WHEN** `nix flake check` runs
- **THEN** it succeeds for the declared outputs

### Requirement: Two Ruby lanes

The flake SHALL provide a primary lane on the current stable Ruby line and a compatibility lane on
the previous stable line, so the supported range is exercised rather than assumed.

#### Scenario: Both lanes resolve dependencies

- **WHEN** the test lanes run in the primary lane and in the compatibility lane
- **THEN** dependency resolution succeeds in each and the same lane names are available in both

### Requirement: Isolated gem resolution

Project dependencies SHALL resolve from project-local gem state, so a broken or mismatched gem
installed in the user's global gem directory cannot affect the build or the tests.

#### Scenario: Broken global gems cannot break the build

- **WHEN** the global gem set contains a native extension built against a different Ruby or missing shared library
- **THEN** the project's lanes still install and run successfully

### Requirement: Test lanes

The project SHALL expose `rake test:unit`, `rake test:protocol`, `rake test:hardware` and
`rake test:all`, where the default lane runs unit and protocol tests and never requires physical
AirPlay hardware, avahi or ffmpeg.

#### Scenario: Default lane has no external requirements

- **WHEN** `rake` runs on a host with no AirPlay device, no avahi and no ffmpeg
- **THEN** the unit and protocol tests run and the hardware tests are skipped rather than failed

#### Scenario: Hardware lane is explicit

- **WHEN** `rake test:hardware` runs without the hardware environment configured
- **THEN** the lane reports its tests as skipped and does not fail the run

### Requirement: Optional integration packages

The flake SHALL make the optional integration and simulator tools — `ffmpeg`, `avahi`,
`shairport-sync`, `owntone` and `uxplay` — available in a dedicated shell or output, without any of
them becoming a hard runtime dependency of the library.

#### Scenario: Integration shell provides the simulators

- **WHEN** the integration shell is entered
- **THEN** `ffmpeg`, `avahi-browse`, `shairport-sync`, `owntone` and `uxplay` are executable, and the default shell still exposes none of them as library requirements

### Requirement: Continuous integration parity

Continuous integration SHALL run the test lanes inside the flake rather than a hand-maintained
Ruby environment, and the obsolete Travis configuration SHALL be removed.

#### Scenario: CI mirrors the dev shell

- **WHEN** the CI workflow runs on a change
- **THEN** it uses the flake-provided toolchain and the same lane commands a developer runs locally

### Requirement: Documented environment

The development environment, lane commands and Ruby lanes SHALL be documented in the repository's
documentation sources, and the generated README SHALL continue to be produced from them.

#### Scenario: Documentation matches the environment

- **WHEN** a new contributor follows the documented setup on a supported platform
- **THEN** the documented shell entry and lane commands run as written, and README generation succeeds
