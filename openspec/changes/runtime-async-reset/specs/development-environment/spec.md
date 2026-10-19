# Spec Delta

## Purpose

A flake-pinned toolchain with isolated gem state makes every dependency reproducible on the
canonical macOS arm64 host without disturbing its Ruby installation.

## ADDED Requirements

### Requirement: Flake-defined toolchain

The repository SHALL declare its toolchain in `flake.nix` with a committed `flake.lock`, so that
`nix develop` provides Ruby, bundler, OpenSSL bindings, `pkg-config`, `jq` and git without relying
on the host's global package set.

```sh
nix develop -c ruby -v
nix develop -c bundle -v
nix develop -c openssl version
```

#### Scenario: Fresh shell has the toolchain

- **WHEN** `nix develop` is entered in a fresh checkout
- **THEN** `ruby -v`, `bundle -v` and `openssl version` all succeed inside that shell

#### Scenario: Flake evaluates cleanly

- **WHEN** `nix flake check` runs
- **THEN** it succeeds for the declared outputs

### Requirement: Latest stable Ruby lane

The default dev shell SHALL provide Ruby 4.0.7, the latest stable release, and the gems SHALL
declare `required_ruby_version >= 4.0`.

```ruby
# airplay.gemspec
s.required_ruby_version = ">= 4.0"
```

```sh
nix develop -c ruby -v
# ruby 4.0.7 (2026-09-15 revision 229531a6cf) +PRISM [arm64-darwin25]
```

#### Scenario: Dependencies resolve on the pinned lane

- **WHEN** the test lanes run in the default shell
- **THEN** dependency resolution succeeds and `ruby -v` reports 4.0.x

### Requirement: Isolated gem resolution

Project dependencies SHALL resolve from project-local gem state, so a broken or mismatched gem
installed in the user's global gem directory cannot affect the build or the tests.

```sh
nix develop -c bundle install
# Bundled gems are installed into `./.nix/gems`
```

#### Scenario: Global gems cannot break the build

- **WHEN** the global gem set contains a native extension built against a different Ruby
- **THEN** the project's lanes still install and run successfully

### Requirement: Test lanes

The project SHALL expose `rake test:unit`, `rake test:protocol`, `rake test:hardware` and
`rake test:all`, where the default lane runs unit and protocol tests and never requires physical
AirPlay hardware or any external service.

```sh
nix develop -c bundle exec rake
nix develop -c bundle exec rake test:hardware
```

#### Scenario: Default lane has no external requirements

- **WHEN** `rake` runs on a host with no AirPlay device
- **THEN** the unit and protocol tests run and no hardware test is attempted

#### Scenario: Hardware lane is explicit

- **WHEN** `rake test:hardware` runs without the hardware environment configured
- **THEN** the lane reports its tests as skipped and does not fail the run

### Requirement: Documented environment

The development environment, lane commands and pinned Ruby version SHALL be documented in the
repository's documentation sources, and the generated README SHALL continue to be produced from
them.

```sh
nix develop -c bundle install
nix develop -c bundle exec rake
```

#### Scenario: Documentation matches the environment

- **WHEN** a new contributor follows the documented setup on the canonical host
- **THEN** the documented shell entry and lane commands run as written, and README generation
  succeeds
