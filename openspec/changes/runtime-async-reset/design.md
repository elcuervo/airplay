# Design

## Context

See `proposal.md` — Why. The constraints that shape this design:

- The existing code cannot load on a supported Ruby (`Fixnum`, `File.exists?`, `Object#taint` are
  gone) and every gem behind its runtime is unmaintained, so there is no incremental migration
  path: the concurrency, HTTP, logging and FSM layers are replaced in one cutover.
- The host is Ubuntu 26.04 with Determinate Nix 3.21.5 (nix 2.34.8). Its *global* gem set is broken
  twice over: a user `openssl-4.0.2` gem whose extension needs a missing `libssl.so.3`, and a
  `json-2.21.1` extension linked against `libruby-3.4.8` under a 3.4.9 interpreter. Anything that
  resolves gems from that directory is unusable for this project.
- No avahi, no ffmpeg on the host. nixpkgs (the flakehub `nixpkgs-weekly` input) carries
  `ruby_4_0`, `ruby_3_4`, `shairport-sync`, `owntone`, `uxplay`, `avahi`, `ffmpeg` and `libplist`;
  its default `ruby` attribute currently resolves to 3.4.9, so "latest Ruby" must be pinned
  explicitly rather than inherited.
- The five sibling changes all build on this one, so the interfaces fixed here — session lifecycle,
  error taxonomy, harness modes — are the project's first real contracts.

## Goals / Non-Goals

**Goals:**

- A session facade with a small, stable surface that protocol changes can implement without
  touching the reactor, the logger or the test lanes.
- A harness that can validate wire formats **without hardware**, bidirectionally (sender against an
  independent receiver implementation).
- A toolchain where a fresh clone reproduces an exact Ruby plus gem set, and where no global gem
  can influence the result.

**Non-Goals:**

- Any protocol behavior (discovery, pairing, video, audio) — later changes own those.
- Any user interface beyond the status/logging events a UI will consume later.
- Multi-process or multi-reactor topologies; a shared clock daemon is deferred with the PTP change.

## Decisions

**Adopt `async` 2.x as the only concurrency model.** Alternatives: keep Celluloid (unmaintained
since 2018 and thread-per-actor, which is the wrong shape for RTP pacing), `concurrent-ruby`
(no fiber scheduler; still needs locks around shared timing state), raw threads with queues
(reimplements scheduling badly). Rationale: fiber scheduling plus structured concurrency gives the
primitives this domain actually needs — a barrier that releases every device of a group at one
instant, a semaphore to bound concurrent connects, a notification to wake a UI on an event-channel
transition — without locking. Trade-off: a single-threaded reactor means any blocking call stalls
every session, which the design treats as a correctness rule and tests for.

**One reactor per process, sessions as child tasks.** Alternative: one reactor per session in its
own thread. Rationale: group starts and a shared clock need one event loop, and cross-reactor waits
would leak threads. Trade-off: sessions must contain their own failures; a test asserts a failing
session does not take the reactor or its peers down.

**Async-first API with a sync facade for one-shot commands.** Alternatives: keep the old
synchronous surface by running a reactor in a background thread (reintroduces the actor problems
this change removes), expose only callbacks (pushes complexity onto every caller). Rationale: the
work is inherently concurrent — playback, timing, event channel and progress run at the same time —
so the core is async and the CLI's one-shot verbs get a small synchronous wrapper. This is the
proposal's declared breaking change.

**`console` for logging and progress.** Alternatives: stdlib `Logger` (no progress or structured
fields), keep log4r (2015), `semantic_logger` (heavier than needed). Rationale: `console` is already
a runtime dependency of `async`, emits structured events with a level filter, and provides the
progress rendering the CLI needs, keeping the machine-readable status stream and the human surface
on one path.

**Replace `micromachine` with an explicit transition table.** Alternative: keep the gem, or adopt
`state_machines`/AASM. Rationale: the use is a four-state playback machine; a table is smaller,
inspectable and directly testable, and the dependency is dead anyway.

**The nix flake is the toolchain authority.** Alternatives: `.ruby-version` plus bundler (already
proved insufficient — the global gem directory is poisoned), Docker Compose (duplicates the
toolchain and cannot express the simulator set as cleanly), `asdf`/`mise` (still share or shadow the
global gem home unless reconfigured). Rationale: the flake locks Ruby *and* the optional integration
packages (`ffmpeg`, `avahi`, `shairport-sync`, `owntone`, `uxplay`) that the harness needs, and it
gives CI the same environment a developer runs. Trade-off: Nix becomes a development prerequisite;
the supported fallback is any Ruby with an isolated `BUNDLE_PATH`, documented but not the reference
environment.

**Harness ships as a separate, dev-only package.** Alternative: keep the fakes under `test/`.
Rationale: both gems' test suites need the virtual receiver, and the runtime gems must not ship it.
Trade-off: one more gemspec to keep in step.

**Clean cutover of the old stack.** Alternative: keep compatibility shims for the removed classes.
Rationale: the last published release predates the removal of the language APIs those classes use,
so there is no reachable consumer to keep compatible; shims would only obscure the new contracts.

## Risks / Trade-offs

- [Async 2.x surface churn] → pin `~> 2.46` and keep the library-facing surface limited to the
  session facade, so an upgrade touches one module.
- [A blocking call silently stalls every session] → a documented rule, a review checklist item, and
  a test that proves a multi-second resolution in one session does not delay another.
- [One session's failure takes down the reactor] → sessions run as child tasks that contain their
  own errors; covered by a test asserting peers survive a session that raises.
- [Flake evaluation needs network on first use] → commit `flake.lock`, cache in CI, and document the
  offline/non-Nix fallback.
- [Ruby 4.0 versus 3.4 differences] → two flake lanes, both exercised in CI; the gem's declared
  minimum is the lower of the two.
- [The breaking API change inconveniences the CLI's own verbs] → the sync facade keeps one-shot
  commands unchanged in shape, and the migration is documented in the generated README.

## Migration Plan

1. Land the toolchain first (flake, lanes, CI) while the old code is still present, so red/green is
   observable before anything is deleted.
2. Swap dependencies and delete the dead stack in one commit; the library loads again
   (`require "airplay"` succeeds) with the session facade stubbed to the old behavior where needed.
3. Replace configuration/logging, then delete the old `Configuration#load`, log4r logger and the
   Rack boot path.
4. Land the harness skeleton and the `test:protocol` lane with one smoke scenario.
5. Rollback: each step is a separate revertible commit; nothing in steps 1–4 depends on a later
   change. The sibling changes must not start until this change is archived, because they consume
   its facade and harness.

## Open Questions

- Which Ruby line is the flake's default lane (Ruby 4.0.x versus 3.4.x) — decided by the first CI run
  on both lanes; both remain supported either way.
- Whether the sync facade also wraps the photo/slideshow path, or only the command verbs — a
  convenience decision taken when the CLI change lands.
