# Design

## Context

See `proposal.md` — Why for the motivation. What shapes the approach:

**What exists today.** `lib/airplay/player.rb` implements the whole video feature as: `POST /play`
with `Content-Location`/`Start-Position` on a persistent socket, `POST /rate?value=` for pause and
resume, `POST /stop`, `POST /scrub?position=`, `GET /scrub` for position, `GET /playback-info` polled
once per second inside a `MicroMachine` state machine (`loading → playing → paused → played →
stopped`), and a `Player::PlaybackInfo` struct reading `duration`, `position`, `rate`,
`playbackLikelyToKeepUp`, `stallCount`, `readyToPlay` out of the plist, with `stopped?` defined as
"the plist is empty". `lib/airplay/cli.rb#play` creates a progress bar and blocks in
`Player#wait`. All of that survives the revival only as the legacy route; the state source changes
underneath it.

**What the sibling changes provide.** `runtime-async-reset`: the `Airplay::Session` facade, structured
cancellation and timeouts, the error taxonomy with machine-readable codes, and the harness lanes with
the in-process virtual receiver. `mdns-discovery`: the typed capability model (video v1/v2,
pairing/access control, `srcvers`). `airplay2-pairing-control`: pair-verify, the encrypted control and
event channels, the plist codec, and route selection. `airplay1-legacy-sender`: the legacy control
plane and the media server with range support.

**The protocol constraint.** On current firmware `POST /command` answers `500` until the sender
registers a remote-control session: `SETUP` with a `type 130` stream, `controlType` 1, and the
stream identifier from that answer carried on every command. The same session declines
`GET /playback-info` — its error is not a playback failure — and reports state on the encrypted
event channel instead. Observed on tvOS 26.5 with three media kinds: a remote HLS stream, a locally
served HLS stream and a locally served progressive file.

**The path is churning.** Three 2026 upstream shapes disagree on details that a constant would have
to guess: sender user agent `AirPlay/550.10` vs `AirPlay/870.14.1` vs `AirPlay/960.13.1`; header
`X-Apple-Stream-ID` vs `X-Apple-StreamID`; channel identifier derived from the sender MAC vs from the
receiver's `/info` identity; `actionAtItemEnd` present or absent in the start sequence; and one
account reports that events only arrive on a PTP-timed video session while the branch validated on
tvOS 26.5 uses the NTP-based session SETUP. Two further hardware findings constrain the sequence:
feedback must not be in flight while queue commands are issued (the same connection carries
sequence-matched RTSP and non-sequence-matched HTTP), and one item field is length-limited on the
receiver with no error response when violated.

**Testability.** The only oracle available in CI is the virtual receiver from `runtime-async-reset`:
there is no physical receiver on this host, and the host's Ruby and gem set cannot run the project at
all, so every scenario in this change is written to be executable against that receiver, with the
hardware lane as an opt-in measurement rather than an acceptance gate.

## Goals / Non-Goals

**Goals:**

- Play a remote URL and a locally served file end to end on the modern route, with the receiver's own
  queue driving playback and the sender's report derived from receiver state.
- One playback-state model, fed by two adapters (event channel, polled playback-info), shared with
  audio playback instead of a second video-only state machine.
- Transport control (pause, resume, stop, seek, rate, next, previous) and queue manipulation
  expressed on the queue surface, with the CLI offering the verbs without knowing the route.
- Now-playing that a modern receiver renders: metadata, artwork, supported commands, playback state,
  playback client, pushed only when something changes.
- Failures that are legible: a bounded retry for the transient case, the pairing error contract for
  `401`/`403`, and typed failures everywhere else.
- The legacy route kept working and selectable, including for receivers whose firmware we do not know.

**Non-Goals:**

- Screen mirroring (FairPlay, H.264 encoding, PTP servo), DRM-protected content, AirPlay 2 photo
  support (see `proposal.md`).
- The MRP device-info origin registration (a protobuf message the audio reference posts before its
  now-playing sequence); this change's now-playing work is the four message shapes it needs, and the
  hardware lane records whether a receiver renders without the registration.
- The legacy DMAP metadata parameter copy, which non-Apple speaker-class receivers consume but which
  has no role in video playback on a screen receiver.
- Buffered audio (type 103), PTP clocking and stream-timing work: they belong to `raop-audio-stream`
  and to the session's timing negotiation.
- Multi-item queue payloads: one item is inserted per play (see Open Questions).
- Re-implementing or restructuring the legacy control plane; this change only consumes it.

## Decisions

### D1. The event channel is the state source; polling is a fallback, and command success never means playing

Rationale: the queue session's state exists only on the event channel, and the legacy endpoint answers
an error inside such a session — treating that error as failure is what tore the picture down
upstream. But not every receiver pushes state (the NTP-timed session experiment observed zero events
while the media played), so a session that stays silent would hang at the startup window with no
state. Rule: derive state from events when they arrive; otherwise poll `GET /playback-info` on a
bounded interval and build the same model; require an observed `playing` transition for a play to be
reported as started; distinguish "did not start" from "ended" so callers and tests see the
difference.

Alternatives: **poll only** (today's code — provably part of a session the receiver no longer
considers a play-queue session, and its status codes are meaningless there); **events only** (a
silent receiver hangs until the session timeout, with no way to tell a stall from a stall-free
picture); **treat the first accepted command as success** (the failure mode this change exists to
remove).

### D2. Wire values are per-firmware profile data pinned by committed fixtures

Rationale: the disagreements listed in Context are all values a real sender takes from its own
version, and every one of them is accepted or rejected outright by the receiver with no
negotiation. Compiling one of them in means the next firmware change is a code change with no test
that could have caught it. A profile carries the sender identification, header spelling, channel
identity derivation, command field names and the expected command shapes; the profile used is logged,
and an unknown firmware falls back to the default profile explicitly rather than silently.

Alternatives: **constants** (the observed failure mode: two upstream rewrites in one year);
**runtime probing of variants** (each wrong request risks the receiver dropping the connection
mid-sequence, and the sequence is not idempotent); **deriving the shape from `/info`** (no reliable
mapping from a reported version to the accepted shape is known).

### D3. Bounded retry, only for the transient case, and never after the item is inserted

Rationale: the receiver does answer `500` transiently and a retry recovers it, but the start sequence
is not idempotent: retrying after `insertPlayQueueItem` succeeded inserts a second item. So the retry
budget (three attempts, one second apart) applies to the first command only, and every other
non-2xx is reported. `401` and `403` are mapped onto the pairing contract's `auth_required` and
`auth_failed` rather than being retried or flattened into one auth error, because the caller has to
tell "needs a password" from "wrong password".

Alternatives: **retry every failure** (auth failures loop, duplicate items); **retry nothing** (the
observed flake becomes a user-visible failure); **exponential backoff** (no evidence that longer waits
help a receiver that answers `500` immediately, and it prolongs the window in which a partial
sequence is on the receiver).

### D4. One route-independent playback-state model, fed by adapters, owned by the library

Rationale: audio streaming, the queue route and the legacy route all report the same quantities
(status, position, duration, rate, ready/stall hints, item identifier, receiver-reported error code
and domain) from different sources, and the CLI, progress rendering and the test lanes want to consume
one shape. Putting the model in the library, with an event adapter and a polling adapter that feed it,
lets `raop-audio-stream` reuse it. Unreported fields are unknown, not zero: today's `has_duration?`
-and-`percent` arithmetic on a missing value silently produces nonsense.

Alternatives: **keep state in the CLI** (today's arrangement; untestable without a terminal and
duplicated per caller); **one state machine per route inside the player object** (two divergent
notions of "playing", and audio gets its own; the current `MicroMachine` transitions read
`info.played?` as "the plist has exactly two keys", which is not a state a receiver reports).

### D5. Two route implementations behind one playback interface

Rationale: the queue route and the legacy route differ in every request they send and agree on what
callers want (play, pause, resume, stop, seek, rate, next, previous) and what they must report (the
state model). Making each a small implementation of one interface keeps the CLI and the session free
of route branching, and gives the harness two implementations to drive. The queue client and the
event-channel adapter are library components, not CLI internals.

Alternatives: **branching inside one player** (the legacy and modern flows interleave in ways that
cannot be asserted separately); **the CLI selecting endpoints from capabilities** (policy duplicated
in the front end, and the CLI becomes the only place the choice can be tested).

### D6. The CLI exposes transport verbs and route status, and never learns the protocol

Rationale: `air pause`, `air stop`, `air seek`, `air next`, `air rate` are the user-facing surface;
which endpoint or command implements them is a route property. What the CLI does need to show is the
decision: the route, the firmware or profile selected and the reason, because that is what a user
reports in a bug and what the hardware lane records.

Alternatives: **per-route CLI verbs** (leaks the protocol into the user's mental model and doubles
the surface); **route hidden entirely** (a fallback that silently serves the legacy path on an
unknown receiver is indistinguishable from a working modern one).

### D7. Unknown firmware degrades to the legacy route by policy, and a refused control stream is not a silent downgrade

Rationale: an optimistic queue attempt on a receiver we cannot identify looks successful (commands
accepted, media fetched) and produces no picture, which is the failure this change is fixing;
conservatism costs only the older, better-understood path. Once the route is chosen, a
refusal of the control stream is reported as a typed protocol failure naming the receiver's status,
because that is evidence the profile or the receiver is wrong, and silently playing through the legacy
endpoint would hide it.

Alternatives: **always request the queue route and fall back on failure** (contradicts route-selected
behaviour, and a failed control-stream setup can leave the receiver's session in an unknown state);
**capability-only decision with no conservative case** (unknown firmware then silently takes the
optimistic path).

### D8. Stop is a rate-zero command followed by item removal

Rationale: neither reference implements stop for the queue route, so this change picks the two
primitives that are proven to be accepted — a rate command, and the queue-item removal that queue
manipulation needs anyway — and pins the sequence in the profile's fixture. Hardware sees it, and the
harness asserts that the session survives for a subsequent play.

Alternatives: **legacy `POST /stop`** (the endpoint's applicability inside a queue session is unknown,
and the same reasoning that made `GET /playback-info` unusable there applies); **tearing the session
down** (a caller that stops and plays again would re-pair, and the receiver leaves playback state
behind).

### D9. Seek is a queue command carrying the position for the item's UUID

Rationale: the item's position representation is already needed for a positioned start, so seeking
reuses it and stays on the command endpoint. The legacy `/scrub` endpoint belongs to the legacy
session; `GET /scrub` is what today's `Player#scrub` uses.

Alternatives: **legacy `/scrub?position=`** (the same session-applicability doubt as stop);
**re-inserting the item with a new start position** (re-fetches the media and discards the queue
position, and a duplicate item is exactly the failure D3 guards against); **an anchored
flush-and-resync, as audio does** (a video URL is decoded by the receiver, not by us — there is
nothing for the sender to flush).

### D10. Now-playing is pushed on the encrypted control channel, change-driven, gated and non-fatal

Rationale: that is the transport and envelope a screen receiver renders, and the reference records
that a bare or invented outer message is rejected outright with a client error, and that pushing on
a timer makes the receiver re-render. The policy follows from what the receiver does with the data
rather than from what we send: full pushes must carry artwork bytes every time (the receiver neither
caches by identifier nor preserves absent keys), timeline-only corrections (seek, and the elapsed
update on pause/resume) use the update merge policy without artwork so the receiver does not re-decode
the cover, pause/resume push the timeline before the state so a receiver does not extrapolate across
the pause, the item identifier changes only with the item, and an identical bundle is not pushed
again. A receiver that rejects the update form is downgraded to full pushes for the rest of that
session, and a rejected push never fails playback.

Alternatives: **the legacy DMAP metadata parameter path** (receivers 200-accept it and do not render
it; it stays relevant only for speaker-class devices); **the type-130 data channel** (a separate
protobuf channel the reference explicitly does not use for now-playing); **re-pushing on a timer**
(re-render churn, and position is extrapolated by the receiver from elapsed time plus rate).

### D11. Local media is handed as a session-scoped URL; remote media is passed through

Rationale: the receiver fetches the media itself, so for a local file we must be reachable and stable:
an absolute URL on the address the session uses with that receiver, served for the session's lifetime,
with the file's content type and range support — and no requirement that the receiver send anything
beyond a standard request. A remote URL is handed over unchanged: proxying it would add a hop, break
playlist-relative fetches and change nothing for the receiver.

Alternatives: **proxying remote media through the sender** (extra hop, HLS becomes our problem);
**handing a file path or `file://` URL** (not fetchable by the receiver); **a per-range URL** (the
session contract is one stable URL per item).

## Risks / Trade-offs

- [The upstream shape changed at least three times in 2026, so any implemented sequence can already be
  stale for the receiver in front of a user] → wire values live in a profile selected from the
  reported firmware, every profile is pinned by a committed fixture with its provenance, and the
  hardware lane records firmware version, profile and outcome per run, so a new firmware is a data
  change plus a capture rather than an archaeology exercise.
- [A retried start sequence can duplicate a queue item when the first attempt was partially applied] →
  the retry budget covers only the first command; a failure after the insert is reported, and the
  receiver double records inserts so the harness asserts exactly one item UUID.
- [A receiver that pushes no state (one hardware account observed zero events on an NTP-timed video
  session) would leave the queue route stateless] → the polled adapter is a first-class fallback with
  its own tests; the startup window fails the play with a distinguishable "did not start" failure
  rather than hanging; the hardware lane records event counts per timing mode.
- [Artwork bytes ride every full push, which costs control-channel bandwidth at track changes and
  pause/resume] → pushes are change-driven only (never on a timer), progress rides the timeline
  fields, and timeline-only corrections use the update form; measured cost is a few tens of kilobytes
  at human-action frequency.
- [The reference posts an MRP device-info origin registration before its now-playing sequence, which
  this change does not implement; a receiver can therefore ignore the pushes] → the virtual receiver
  asserts the four message shapes this change does own, and the hardware lane records whether the
  receiver renders now-playing and what it shows; a negative observation is a follow-up change, not a
  silent regression, and the now-playing push is disableable and never fatal to playback.
- [The queue route can fail in ways that look successful: commands accepted, media fetched, no picture]
  → the capability-driven route policy keeps unknown firmware on the legacy path, the play completes
  on receiver-reported state, and the queue inspection (`GET /playback-info` erroring, no events) is
  treated as evidence about the route rather than about the media.
- [Profile data drifts from what the code sends] → fixture comparison is part of the protocol lane, and
  the profile's provenance note names the firmware each capture came from.
- [Building now-playing and transport on the queue route could destabilize the legacy route, which is
  the only path that works on older receivers] → both routes implement one interface, the legacy route
  keeps its own lane coverage, and the CLI's route-status output makes the path in use visible.

## Open Questions

- Whether a single `insertPlayQueueItem` can carry several items, so a playlist could be handed to the
  receiver as one queue instead of one insert per item. Deferred: this change inserts one item per
  play and sequences playlist entries per item, the fixtures record the single-item shape, and
  answering the question later adds a payload form without changing the specifications above.
