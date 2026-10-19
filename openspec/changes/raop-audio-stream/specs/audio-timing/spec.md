# Spec Delta

## Purpose

Keeps audio aligned with the wall clock: an NTP-style timing responder, the announcements that anchor RTP positions to time, the anchor and pacing rules that make a scheduled start audible at the intended instant, re-anchoring after a flush, and the defined outcome when a receiver cannot be timed.

## ADDED Requirements

### Requirement: The Session Answers Clock Requests

Each audio session MUST run a UDP timing responder on the port advertised in setup and MUST answer every well-formed timing request with a reply that echoes the requester's send timestamp as the reference timestamp and carries our receive and transmit timestamps, all as NTP-epoch 64-bit fixed-point values. A datagram too short to be a timing request MUST NOT produce a reply or end the session.

#### Scenario: Reply echoes the reference timestamp

- **WHEN** a receiver sends a timing request carrying its send timestamp
- **THEN** the reply's reference timestamp equals that send timestamp and its receive and transmit timestamps come from our clock

#### Scenario: Timestamps use the NTP epoch

- **WHEN** the responder stamps a reply
- **THEN** the seconds field is the Unix time plus the NTP epoch offset, so a receiver converting it back recovers the same instant

#### Scenario: A malformed datagram is ignored

- **WHEN** a truncated or unrecognizable datagram arrives on the timing port
- **THEN** no reply is sent and the session keeps answering later requests

### Requirement: Time Announcements Anchor RTP Positions To The Wall Clock

While content flows, the sender MUST send at least one announcement per second to the receiver's control port carrying the session timeline's RTP position and the wall-clock instant it corresponds to, in NTP-epoch timestamps. The first announcement after record, and the first after a flush, MUST be marked, and MUST be sent before the content it anchors.

#### Scenario: One announcement per second

- **WHEN** a session plays for ten seconds with the harness clock advanced in real time
- **THEN** the receiver's control port receives at least ten announcements

#### Scenario: Announcements carry both positions

- **WHEN** an announcement is sent
- **THEN** it carries the wall-clock instant, the RTP position audible at that instant, and the current RTP position of the send head

#### Scenario: The first announcement is marked and early

- **WHEN** content starts or restarts after a flush
- **THEN** the first announcement of the run is marked and arrives before the first audio packet of the run

### Requirement: Announcements Extrapolate One Frozen Anchor Line

The mapping between RTP positions and wall-clock time MUST be fixed once per anchor, and every announcement MUST be extrapolated along that same mapping. The sender MUST NOT re-derive the mapping from its send head per packet, because inconsistent re-anchoring makes receivers re-seat their timeline and drop buffered audio.

#### Scenario: Consecutive announcements agree

- **WHEN** the harness sink converts three consecutive announcements to (instant, position) pairs
- **THEN** the implied rate between every pair is the session sample rate within the harness tolerance

#### Scenario: Filling the buffer does not move the line

- **WHEN** the send head races ahead while the receiver's buffer is being filled
- **THEN** the anchored mapping still extrapolates to the same line as the first announcement

### Requirement: A Start Is Anchored To A Wall-Clock Instant

A start MUST be anchored to a wall-clock instant at which the first content sample becomes audible. The sender MUST refuse an instant earlier than the earliest feasible one — the current time plus the minimum lead — by correcting it forward, and MUST report the instant it actually anchored to. An absent or past instant MUST be treated as the earliest feasible one.

#### Scenario: A feasible instant is honoured exactly

- **WHEN** a start is requested an instant at or beyond the earliest feasible one
- **THEN** the reported anchored instant equals the requested instant

#### Scenario: A past instant is corrected forward

- **WHEN** a start is requested for an instant in the past
- **THEN** the sender anchors to the earliest feasible instant and reports the corrected value to the caller

#### Scenario: The minimum lead covers the commit round trips

- **WHEN** a start is requested less than the minimum lead ahead of now
- **THEN** the anchor is corrected forward to now plus the minimum lead rather than committed to an instant it cannot reach

### Requirement: Delivery Is Paced Against The Anchor Deadline

Frames MUST be released against their anchor deadline: a frame MUST be delivered early enough to fill the receiver's buffer but never more than the pacing window ahead of its deadline, and a sender that has fallen behind MUST catch up by sending additional frames rather than dropping content. Delivery MUST NOT run ahead of the window even when the source has more content ready.

#### Scenario: The window bounds how far ahead delivery may run

- **WHEN** the harness sink timestamps every packet of a run against the injected clock
- **THEN** no packet is delivered more than the pacing window before its deadline

#### Scenario: Falling behind catches up instead of skipping

- **WHEN** the source stalls past a frame's deadline and delivery resumes
- **THEN** the sender sends the frames it owes, keeps sequence and timestamp continuity, and drops no content

#### Scenario: A slow sink does not stretch the schedule

- **WHEN** the harness sink acknowledges more slowly than real time while the injected clock is held still
- **THEN** the sender sends nothing further until the clock advances past the next frame's release point

### Requirement: The Pacing Window Comes From The Receiver's Reported Latency

When the receiver reports a latency window, the pacing window and the start lead MUST be clamped into the reported minimum and maximum frames; when it reports none, the sender MUST use a default inside the standard two-second window. A receiver-reported downstream render latency MUST NOT shift the anchor.

#### Scenario: A reported window clamps the lead

- **WHEN** the stream setup reply reports a maximum latency below the default lead
- **THEN** the effective lead and the pacing window are no larger than that maximum

#### Scenario: No reported window falls back inside the standard window

- **WHEN** the reply carries no latency window
- **THEN** the sender uses a default lead inside the standard two-second window and records that the window was assumed

#### Scenario: Reported render latency is informational

- **WHEN** the reply reports a downstream render latency
- **THEN** the anchored instant is unchanged and the value is only reported to the caller

### Requirement: Flush Re-Anchors The Timeline

After a flush the sender MUST re-anchor: it MUST discard timeline positions the receiver no longer holds, fix a new anchor line, send a marked announcement for it, and MUST NOT deliver a frame whose deadline falls before the new anchor. Re-anchoring MUST NOT change the stream key or restart the sequence numbering.

#### Scenario: A new line is announced after the flush

- **WHEN** a session flushes and then starts again
- **THEN** a marked announcement names the new line before any audio packet of the new run

#### Scenario: Positions the receiver dropped are not reused

- **WHEN** the receiver has discarded its buffer at the flush
- **THEN** no audio packet sent afterwards carries a deadline from the discarded timeline

#### Scenario: Sequences and key survive the flush

- **WHEN** the new run's first packet is compared with the pre-flush packets
- **THEN** the stream key is unchanged and the sequence number continues without restarting

### Requirement: Untimed Receivers Are Reported

A session that cannot establish a clock exchange — no timing request answered and no announcement accepted — MUST report its timing state as not established within a bounded window instead of assuming the clock is shared, and that state MUST be observable before a start is scheduled.

#### Scenario: Silence from the receiver is detected

- **WHEN** a session's clock window closes with no timing request received and no evidence of a shared clock
- **THEN** the session reports timing as not established and names the receiver as the cause

#### Scenario: A late exchange clears the state

- **WHEN** the receiver answers after the window closed
- **THEN** the session reports timing as established and a scheduled start is allowed to proceed

### Requirement: Audio Is Never Played Before Its Anchor

Content MUST NOT be made audible before the instant it is anchored to, and content MUST NOT be discarded to hide an anchor that could not be seated. A start the session cannot seat MUST be corrected forward and reported, or fail with a coded timing error; silence MUST NOT be sent in place of content to fake a start.

#### Scenario: An unseatable start is not played early

- **WHEN** a start is scheduled for a receiver that cannot be timed and the instant passes
- **THEN** no content is delivered for that instant and the caller receives a coded timing error or a corrected forward instant

#### Scenario: Silence does not stand in for content

- **WHEN** a start is corrected forward
- **THEN** the frames delivered around the correction are the source content for that instant, not padding standing in for an earlier instant

### Requirement: Timeline Arithmetic Uses The Injected Clock

All timeline arithmetic MUST read wall-clock and monotonic time from the session's injected clock source, so a harness can drive an anchor, a stall or a flush deterministically without waiting in real time.

#### Scenario: A frozen clock freezes the schedule

- **WHEN** the harness holds the injected clock still and observes the sender
- **THEN** no deadline passes, no announcement is emitted and no packet is delivered until the clock advances

#### Scenario: Advancing the clock advances the schedule

- **WHEN** the harness advances the injected clock past a frame's release point
- **THEN** exactly the frames whose deadlines have passed are delivered, in order
