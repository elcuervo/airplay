# Proposal

## Why

The revamped project currently has no audio at all, and audio is the one capability a modern
receiver will accept from a non-Apple sender without FairPlay: RAOP/RAOP-compat streaming is
implemented by every open-source sender in the ecosystem, and the working reference (pyatv)
streams **raw PCM** (`ct: 1`, `audioFormat 0x800`, 352 samples per frame, 44.1 kHz) rather than
requiring an ALAC encoder, encrypting each RTP packet with a per-stream key and an 8-byte nonce.
Audio also unlocks what this tool has never had: synchronized multi-room playback, where the
whole point is that every device starts at the same instant — the current group implementation
just polls `sleep 0.1 while still_playing?`. Doing this now builds directly on the pairing and
control plane, and it is the last core capability missing before the project can credibly claim
AirPlay 2 compatibility.

## What Changes

- Implement the two-phase RAOP/AP2 `SETUP`: phase one for session identity and timing
  negotiation (advertising our timing port and protocol), phase two for the audio stream
  definition (`type 96` realtime, or `type 103` buffered when the device advertises buffered
  audio), with the negotiated `shk` stream key, sample rate, frame size and declared latency
  window.
- Send audio as RTP over UDP: sequence, timestamp and SSRC management, payload AEAD with
  ChaCha20-Poly1305 using the stream key and the 8-byte trailing nonce, correct AAD, and
  packet-size and pacing limits derived from the device-reported latency window.
- Support PCM (uncompressed) first, which needs no encoder, and ALAC second, negotiated from the
  device's `cn` field; optionally obtain PCM for inputs we cannot decode natively through
  `ffmpeg` from the dev shell, with that dependency remaining optional at runtime.
- Implement timing: an NTP-style timing responder and the sync packets that anchor the RTP
  clock to the wall clock, the anchor/pacing model that makes a scheduled start audible at the
  intended instant (lead, buffer depth, and re-anchoring on flush), and a clean fallback when a
  device advertises PTP but cannot be timed.
- Implement volume on the ecosystem convention (linear-in-dB mapping onto −30..0 dB, sent as a
  parameter) so a slider position is equally loud across protocols.
- Implement group playback with a shared start instant: one session per device, a barrier that
  releases every stream at the same anchor, and per-session timeline offsets so two streams
  from one host are not wire-identical twins.
- Expose the streaming surface (`play`, `pause`, `resume`, `stop`, `seek`, volume, progress,
  queue) consistently with the video path, so the CLI/TUI can treat both uniformly.
- Explicitly not in this change: PTP (gPTP, UDP 319/320, unicast negotiation, shared clock
  daemon) is deferred to a follow-up change and is not scaffolded here; hi-res, surround,
  Atmos, announcements/ducking, ALAC 24-bit and the FairPlay-protected audio path are all out
  of scope.

## Capabilities

### New Capabilities
- `raop-audio`: realtime (and buffered) audio streaming to AirPlay/RAOP receivers — session
  setup, RTP transport with per-packet encryption, PCM/ALAC selection, volume and transport
  control.
- `audio-timing`: the clock and scheduling model that makes a stream start and stay aligned —
  timing responder, sync announcements, anchor and pacing rules, and the behavior when a device
  cannot be timed.
- `group-playback`: synchronized playback across several devices, with a shared start instant,
  per-session offsets and a barrier-based release.

### Modified Capabilities
- `airplay2-control-channel` (introduced by the sibling change `airplay2-pairing-control`) grows
  here with the audio stream `SETUP` phase, the stream key exchange, the buffered/realtime
  distinction and the `RECORD`/`FLUSH`/`TEARDOWN` lifecycle.
- `route-selection` (introduced by the sibling change `airplay2-pairing-control`) grows here with
  timing mode (PTP versus NTP) and stream type (realtime versus buffered) selection, including the
  fallback when the advertised timing mode cannot actually be established.
- `test-harness` (introduced by the sibling change `runtime-async-reset`) grows here with the
  audio transports and their decrypting sink, the framing, sealing, pacing, fault and timing-mode
  knobs, the multi-room tolerance run, the audio conformance vectors and the codec-lane reporting.
- All three deltas are `ADDED`, not `MODIFIED`: none of these capabilities exists under
  `openspec/specs/` until the owning change is archived, and `MODIFIED` with partial content loses
  detail at archive time.

## Impact

- Requires `runtime-async-reset` and `airplay2-pairing-control`; adds a new audio/transport
  library subtree and reworks `lib/airplay/group.rb` and `lib/airplay/group/players.rb`, whose
  polling-based waiting is replaced by anchored, barrier-released sessions.
- `ffmpeg` is available from the flake's integration shell for input decoding and conformance
  work but is never a hard runtime dependency; the protocol path itself is pure Ruby.
- Harness slice: an RTP sink that decrypts and asserts sequence continuity, timestamps, SSRC,
  AEAD layout, nonce derivation and pacing against an injectable clock; injection of jitter,
  reordering, packet loss and a device that never acknowledges timing; and a synthetic
  multi-room harness that fails if two sessions do not start within the tolerance the spec
  defines.
- Follow-up work named but not scaffolded here: `ptp-timing` (PTP engine plus shared clock
  daemon) and the interim compatibility matrix that records which real devices were verified
  for which stream type.
