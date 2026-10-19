# Proposal

## Why

Playing a URL or local file on an Apple TV is this tool's headline feature, and on current
firmware the path it uses no longer exists. The legacy `POST /play` with `Content-Location`
breaks on tvOS 26.x (HTTP 500 on 26.2); the upstream Python client only recovered by moving to
the AirPlay 2 **play-queue** flow — an encrypted session, a `type 130` control stream obtained
through `SETUP`, and queue commands sent as binary plists to `POST /command`, with playback
state read from the encrypted event channel rather than guessed. That flow is verified against
tvOS 26.5 for remote HLS, local HLS and local progressive MP4. Without it, the revival ships
with a flagship feature that only works on receivers old enough to accept the deprecated
endpoint.

## What Changes

- Implement the modern video control flow on top of the pairing/control plane: `SETUP` a
  `type 130` URL control stream (client UUID, client type, channel ID, `controlType 1`), then
  send the queue as `POST /command` bodies whose payload is a binary plist —
  `insertPlayQueueItem` (URL, item UUID, start position), `setProperty` for
  `isInterestedInDateRange` and `actionAtItemEnd`, and `setRate` — with the command sequence
  and headers that current firmware accepts.
- Drive playback state from the encrypted event channel (`playbackState` transitions) instead
  of treating the first successful command as success, and keep `GET /playback-info` polling as
  the fallback for devices that report less on the event channel; surface duration, position,
  rate and error codes (including the `error`/`code`/`domain` shape) as a single playback-state
  model.
- Implement transport control on this path: play, pause/resume, stop, seek, next/previous,
  queue manipulation, and playback rate — mapped onto the queue/`setRate`/`setProperty`
  surface rather than the legacy `/rate` and `/scrub` endpoints where the device is modern.
- Report now-playing to the receiver so it renders its own on-screen UI, over the same
  encrypted channel: MediaRemote now-playing metadata (title, artist, album, duration, elapsed,
  rate, timestamp, artwork and its MIME type), supported commands, playback state and the
  playback client representation, re-sent on every state change rather than on a timer.
- Keep the legacy `POST /play` flow (from `airplay1-legacy-sender`) as the fallback for older
  receivers, selected by route rather than by failure.
- Make failures reproducible and legible: retry the transient `500` cases with a bounded
  policy, and map `401`/`403` onto the pairing error contract (`auth_required`/`auth_failed`)
  with the machine-readable status line callers depend on.
- Explicitly not in this change: screen mirroring (FairPlay plus H.264 encoding and PTP servo),
  DRM'd content, and AirPlay 2 photo support — all out of scope.

## Capabilities

### New Capabilities
- `video-playback`: URL and local-file video playback on modern receivers via the play-queue
  command flow, including queue management, transport control, seeking and the bounded retry
  and error contract.
- `now-playing`: pushing MediaRemote now-playing state, artwork and supported commands so the
  receiver's own UI reflects what the sender is playing.
- `playback-state`: the unified playback-state model driven by event-channel transitions with
  `/playback-info` fallback, owned jointly with audio playback.

### Modified Capabilities
- `airplay2-control-channel` (introduced by the sibling change `airplay2-pairing-control`) grows
  here with the `type 130` control stream, the `/command` request shape and event-channel playback
  notifications.
- `media-serving` (introduced by the sibling change `airplay1-legacy-sender`) grows here with the
  contract for URLs served to modern receivers, which fetch media over the same connection
  semantics.
- `test-harness` (introduced by the sibling change `runtime-async-reset`) grows here with the
  play-queue receiver mode, the recorded-traffic assertion surface for exact command order and
  payloads, this route's fault knobs, and the video hardware-lane coverage.
- These deltas are `ADDED`, not `MODIFIED`: none of these capabilities exists under
  `openspec/specs/` until its owning change is archived, and `MODIFIED` with partial content loses
  detail at archive time.

## Impact

- Requires `runtime-async-reset`, `mdns-discovery` and `airplay2-pairing-control`; rewrites
  `lib/airplay/player.rb` and the `play` verb of `lib/airplay/cli.rb` on top of the new session.
- Introduces the queue/command client and the event-channel state machine as first-class
  library components rather than CLI internals.
- Harness slice: a virtual receiver that accepts the `type 130` stream, asserts the exact
  command order and plist payloads, and emits scripted event-channel state transitions
  (playing → paused → stopped, plus a device that never transitions); replay fixtures for the
  captured command shapes; and an opt-in hardware lane against a real tvOS device, with
  firmware version and outcome recorded per run.
- Known churn risk: this exact upstream path changed twice during 2026, so the queue commands,
  headers and user agent are treated as version-sensitive data with fixtures, not as constants.
