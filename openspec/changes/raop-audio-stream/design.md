# Design

## Context

The repository currently has no audio code at all: `lib/airplay/` contains discovery, the legacy
control plane and the group scaffolding (`lib/airplay/group.rb`,
`lib/airplay/group/players.rb`), and nothing that opens an RTP socket. The pieces this change
builds on arrive from sibling changes: the session facade, structured cancellation, the error
taxonomy, the injectable clock and the test lanes from `runtime-async-reset`; the authenticated,
encrypted control channel, the plist codec and the buffer model from `airplay2-pairing-control`;
the typed capability record (feature mask, `cn`/`et`/`sr`/`ss`/`ch`/`md`, `flags`) from
`mdns-discovery`. See `proposal.md` — Why for the motivation; this document covers only the
choices the specs leave open.

Constraints that shape the approach:

- No Ruby ALAC encoder exists in the ecosystem, and the protocol path MUST stay pure Ruby
  (`ffmpeg` is available only from the flake's integration shell and is never a runtime
  dependency).
- The open references agree on the audio wire layout and disagree on details. pyatv
  (`pyatv/protocols/raop/protocols/airplayv2.py`, `support/chacha20.py`) sends PCM with
  `ct: 1`/`audioFormat 0x800`/`spf: 352` at 44.1 kHz and seals each packet with an
  eight-byte counter nonce. owntone (`src/outputs/raop.c`) and the community AirPlay 2 sender
  write-up (`lmcgartland/airplay2-rs`, `AIRPLAY_2_SPEC.md`) place the RTP sequence number in the
  nonce at offset 4. `music-assistant/airplay-cli` (`DESIGN.md`) records hardware findings for
  both derivations and for the trailer order (tag before nonce). Both derivations are described
  as working, so the design picks per stream type and pins the choice with conformance vectors.
- Receivers serialize the stream-setup reply in varying key order; reading ports positionally
  sends audio to the control port and mutes the device.
- Report key order in a stream definition's latency fields and the buffered anchor are not
  uniform: realtime streams are given `latencyMin`/`latencyMax`, buffered streams must not be.
- PTP (gPTP, ports 319/320, unicast TLV negotiation, shared clock daemon) is out of this change
  and arrives with the `ptp-timing` follow-up, so every session here is timed by the NTP
  responder.

## Goals / Non-Goals

**Goals**

- A paced, sealed RTP audio path that works against the in-process virtual receiver without
  hardware, for both a realtime datagram stream and a buffered framed stream.
- One audio engine serving both control handshakes this project must support: the two-phase
  binary-plist setup of an AirPlay 2 native session and the SDP/transport-header setup of a
  RAOP-compat session.
- A timing and anchor model that makes a scheduled start audible at the instant the caller asked
  for, and that degrades loudly rather than playing early when a receiver cannot be timed.
- Group playback that replaces the interval-polling wait in `lib/airplay/group/players.rb` with a
  barrier-released, anchored start and a tolerance the harness can fail a run on.

**Non-Goals**

- PTP/gPTP, ports 319/320, unicast TLV negotiation and the shared clock daemon — deferred to
  `ptp-timing`, and recorded as such in the route-selection delta (a PTP-advertising receiver is
  timed by the NTP responder until that change lands).
- 24-bit and hi-res ALAC, surround, Atmos, announcement ducking, and the FairPlay-protected audio
  path.
- MediaRemote/MRP now-playing: the Apple TV on-screen now-playing path belongs with the
  video/play-queue capability, not the audio transport.
- Perceived-loudness normalisation across ecosystems, manual per-receiver latency trim, and any
  user-visible equalisation.

## Decisions

### One audio engine, two control handshakes

The RTP transport, sealing, timing responder, anchor and pacing code is written once and takes
the stream parameters (payload type, ports, codec, key, latency window) from whichever handshake
produced them: the AirPlay 2 native path runs phase one (identity plus timing negotiation) and
phase two (the stream definition) as binary plists on the authenticated channel; a RAOP-compat
path announces the SDP and performs setup with a transport header naming our control and timing
ports, then feeds the same parameters in. Alternatives considered: AirPlay-2-native only (drops
AirPort Express and Apple TV 3 audio, the compatibility floor the project keeps on purpose);
two separate engines (duplicates sealing, pacing and timing, and guarantees they drift apart).

### PCM first, ALAC gated on an encoder

Uncompressed PCM (`ct: 1`, `audioFormat 0x800`, 352 frames per packet, 44.1 kHz) is the primary
and default path, matching the one open sender that streams to production receivers today. ALAC
is selected only when the receiver's codec advertisement lacks PCM but lists ALAC **and** an
encoder is available; otherwise the session fails with a coded error instead of sending a codec
the receiver never advertised. Alternatives: ALAC first (needs a Ruby ALAC encoder that does not
exist, or makes `ffmpeg` a hard runtime dependency, which the flake contract forbids); ALAC by
linking a native codec (build and packaging cost, and it breaks the pure-Ruby protocol path);
PCM-only forever (leaves the higher-quality path and the eventual hardware matrix with nothing to
grow into).

### `ffmpeg` at the input edge, never in the protocol path

Inputs the sender cannot decode natively are piped through `ffmpeg` from the flake shell into the
same raw PCM reader the native WAV reader uses, so the streaming path sees one PCM source
interface. The no-`ffmpeg` path stays fully working for WAV/PCM. Alternatives: a native extension
against libav* (packaging, ABI and pure-Ruby-path costs); requiring callers to pre-decode
everything (pushes the work onto every caller and makes the CLI useless for common formats);
bundling a decoder (licensing and size).

### Sealing: ChaCha20-Poly1305 with a trailer of tag then nonce

Each packet is `[12-byte RTP header][ciphertext][16-byte tag][8-byte nonce]`, keyed by the
session's 32-byte stream key, with the RTP timestamp and SSRC as additional authenticated data
and a 12-byte nonce whose first four bytes are zero. The transmitted eight bytes are derived from
the packet's position: the realtime stream uses the RTP sequence number (so a retransmission is
byte-identical to its original and the receiver can validate the nonce against the sequence),
while the buffered stream uses a per-packet counter, because a two-byte sequence would wrap and
reuse a nonce inside a long session. Alternatives: pyatv's counter for both (retransmitted
packets would not be byte-identical unless the counter were rewound, which is exactly the state
that invites nonce reuse); sequence for both (wraps on the buffered path); AirPlay 1's
RSA-AES-CBC (needs the FairPlay/RSA key exchange this change does not implement).

### Stream type follows capability and timing, decided before setup

The stream definition declares buffered audio only when the receiver advertises buffered audio
**and** the session holds an established timing route whose timeline the buffered anchor can
express; otherwise realtime. Because PTP is deferred, every session in this change is NTP-timed
and therefore realtime, and the route-selection delta requires that fallback to be recorded and
reported rather than silently assumed. Alternatives: always prefer buffered on a
buffered-capable receiver (a buffered anchor on an unestablished timeline seats nothing);
always realtime (loses the buffered path the capability advertises, and makes the framing work
unreachable).

### Async task structure for a paced sender

One supervised task per session owns the sender. It pulls a frame chunk, seals it, then awaits
the next release point on the session's clock and sends; a stall that pushes the sender behind
releases additional frames up to a bounded catch-up count instead of skipping content. The
timing responder, the announcement ticker and the control-channel reader are separate supervised
tasks, and session cancellation tears all of them down (structured concurrency from
`runtime-async-reset`). Alternatives: one task per packet with `sleep` between (thousands of
timers, drift under load, no catch-up); a dedicated thread per stream (contradicts the
async-first runtime and the session task tree); pushing from the decoder into a queue and letting
a writer drain it (still needs the pacing decision, just further from the data).

### Injectable clock for timeline arithmetic

All anchor, pacing, announcement, readiness and group-barrier arithmetic reads one clock object
supplied by the session, defaulting to the system clock. The harness holds it still or advances
it by explicit amounts, which is what makes the pacing and group-completion assertions executable
without real waiting. Alternatives: calling the system clock directly (the harness would have to
sleep); stubbing time globally (brittle, and it points the test at the wrong seam).

### The anchor model

At a start the sender freezes one anchor line: the wall-clock instant the first sample becomes
audible, clamped to a lead inside the receiver's reported window (defaulting to the standard
two-second lead when nothing is reported), and every announcement extrapolates along that frozen
line rather than re-deriving it from the send head. A commanded instant earlier than the earliest
feasible one (now plus a 250 ms minimum lead) is corrected forward and reported; a receiver that
reports a downstream render latency has that value reported but never added to the schedule,
because receivers already compensate their own render latency. Alternatives: deriving each
announcement from the current send head (consecutive announcements disagree, and receivers
re-seat their timeline and drop buffered audio); trusting the commanded instant unconditionally
(produces the early-playback and echo artifacts the group work exists to remove); applying the
reported render latency (over-compensates and makes those devices early).

### Pacing window and buffered back-pressure

The pacing window is the receiver's reported latency window less a margin when it is reported, a
conservative default inside the standard two seconds otherwise. On a buffered stream the receiver
pulls on its own schedule, so a full socket or a long read pause parks unwritten bytes and the
sender resumes; no send deadline is allowed to end a session. Alternatives: unbounded delivery
(overruns and drops at the receiver); treating a full socket as failure (the reference
implementation removed its buffered path once for exactly that bug).

### Timing failure degrades loudly

NTP is the timing mode this change implements; PTP is a later change. A receiver that never
completes a clock exchange is reported as untimed within a bounded window, and an unseatable
start is corrected forward and reported or fails with a coded timing error — content is never
made audible before its anchor and silence is never substituted for content to fake a start.
Alternatives: optimistic start (audible drift and echo, and the failure is indistinguishable from
network trouble); waiting indefinitely for the clock (hangs the group start); implementing PTP
now (out of scope, needs ports 319/320 and a shared clock daemon).

### Volume on the ecosystem curve

A percentage maps linear-in-dB onto −30..0 dB, zero is sent as the ecosystem's muted value, and
the value goes to the receiver as the volume parameter. No gain is applied locally, so identical
content produces identical packets at every volume. Alternatives: linear amplitude mapping (wrong
loudness curve and inconsistent with other senders); the full 0..−96 dBFS scale (a slider
position would not match other senders); applying gain locally (changes the wire content,
breaks group loudness alignment and would need re-encoding).

### Group start: barrier plus shared instant, tolerance as the verdict

A group start chooses one instant, binds and anchors every member against it behind a barrier,
and releases all senders together. Each session carries a session-derived timeline offset — both
in its sequence numbering and in its RTP offset — which its anchor absorbs, so two members of one
group are never wire-identical twins (receivers with household-wide stream tracking cross-wire
identical streams and silence the stricter one). The start is reported as synchronised only when
every member's reported audible instant is within 50 ms of the shared instant; a member outside
it is named with the instant it used. Completion is driven by each session's drain state, not by
an interval poll. Alternatives: the sequential start the current group code approximates
(members start audibly staggered); a device-side group start (needs PTP and `SETPEERS`, deferred);
per-process offset only (two sessions in one process would still be identical); a looser or
tighter tolerance (the reference implementation's own clock comparisons use 50 ms, and receivers
self-seat a fresh session within roughly 20 ms).

### Metadata on the DMAP parameter surface, gated on the advertisement

Title, album and artist go out as DMAP-tagged fields in a DMAP container, artwork as an image
parameter carrying the session's RTP information, progress as a start/now/end parameter on the
session timeline — each only when the receiver advertises that metadata type (speaker-class
receivers withhold audio until they have metadata, and some reject a metadata request without RTP
information). Alternatives: pushing MediaRemote now-playing here (that is the video/control path's
job and is not needed for audio playback); sending metadata unconditionally (requests a receiver
never advertised, and noise on the control channel).

### Bounded retransmission backlog

The retransmission backlog is a ring over the most recently sent packets (a thousand, the
reference's figure), which bounds memory for a long session; a request for an evicted sequence
number is reported as a miss rather than answered with a guess. Alternatives: unbounded retention
(memory grows with session length); no backlog at all (every lost datagram becomes a glitch even
though the receiver asked for it).

### Where the harness lives

Everything the harness must provide — the audio transports on the receiver double, the
decrypting sink and its framing, sealing, pacing and marker assertions, the fault knobs, the
timing modes, the multi-room tolerance run and the conformance vectors — is specified as an
`## ADDED` delta to the `test-harness` capability owned by `runtime-async-reset`, with requirement
names prefixed by this change's domain. The sender-side requirement that timeline arithmetic uses
the injected clock stays in `audio-timing`, because it constrains the sender. Alternatives:
listing the harness requirements inside the product capabilities (mixes "what the wire must do"
with "how we check it", and those capabilities would then own the double).

## Risks / Trade-offs

- [Buffered anchors are only observed on PTP-timed sessions in the references we have] →
  Buffered selection is gated on an established timing route (route-selection delta), the virtual
  receiver implements the buffered anchor on the session timeline, and real-device verification of
  buffered-on-NTP is an entry for the interim compatibility matrix named in `proposal.md`; the
  `ptp-timing` follow-up makes PTP routes the buffered default.
- [No Ruby ALAC encoder, so the ALAC lane cannot be exercised everywhere] → PCM is the default and
  the tested lane; the ALAC lane requires an encoder and reports itself skipped with the missing
  dependency named rather than passing silently.
- [`ffmpeg` presence changes behaviour between machines] → The codec and decode decision is
  recorded on the session and reported; the dependency-free WAV/PCM lane is the default lane, and
  no protocol-path test depends on `ffmpeg`.
- [A sequence-derived nonce repeats if a long realtime session wraps its sequence numbers] →
  Realtime sessions are short-lived relative to a 16-bit wrap at 352 frames per packet, and the
  buffered path, which is the long-session path, uses the counter nonce.
- [A too-shallow pacing window starves receivers with a deep render floor] → The window follows
  the receiver's reported bounds when present, the default sits inside the standard two seconds,
  and the harness has an explicit starvation assertion.
- [Applying the reported downstream render latency would make Apple receivers early] → The value
  is informational only and is never added to the schedule; a scenario pins that.
- [Receiver read pauses on a buffered stream look like a fault] → Parked bytes plus no send
  deadline is a spec requirement, and the harness asserts a multi-second read pause completes
  cleanly.
- [Group tolerance is a judgement call] → The 50 ms tolerance and the per-member reported instants
  are both required outputs, so a run can be judged against the number it was given rather than
  an implicit one.
- [The two control handshakes could drift apart] → Both feed the same parameter set into one
  engine; the handshake differences are confined to the setup module, and the harness asserts the
  same framing and sealing results for both.
- [Stream key handling is a security surface] → The key is 32 bytes, generated per session,
  carried only in the phase-two definition, kept out of logs and the credential store, and
  forgotten at teardown; a scenario asserts the persistent state stays clean.

## Open Questions

- The concrete shape of the `ffmpeg` invocation at the input edge (which container and codec
  combinations are passed through it, and the argument set used) can be settled during
  implementation without changing the specs, the approach or the task breakdown, provided the
  WAV/PCM path stays dependency-free and the codec decision stays recorded on the session.
