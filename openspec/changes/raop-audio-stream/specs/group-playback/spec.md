# Spec Delta

## Purpose

Plays the same content on several receivers at once: one session per device, a barrier that releases every member at a single shared instant, per-session timelines so members are not wire-identical, and a tolerance that decides whether a start was actually synchronised.

## ADDED Requirements

### Requirement: A Group Holds One Session Per Device

A group MUST hold at most one streaming session per device. Adding a device that already has a session MUST reuse that session rather than opening a second one to the same device, and a session MUST NOT be owned by two groups at once.

#### Scenario: The same device is added twice

- **WHEN** a device with a live session is added to a group that already holds it
- **THEN** the group still holds one session for that device and the receiver sees no second setup

#### Scenario: A second group cannot steal a busy device

- **WHEN** a second group is asked to play to a device whose session another group owns
- **THEN** the second group reports the device as busy and does not open a competing session

### Requirement: Members Start At One Shared Instant

A group start MUST choose a single wall-clock instant shared by every member, and each member's stream MUST be anchored to that instant; a member MUST NOT begin content for any other instant. Release MUST be synchronised through a barrier so that no member writes content before every member has a bound, anchored stream.

#### Scenario: Every member is bound before the first packet

- **WHEN** a group start releases
- **THEN** each member's stream was bound and anchored before that member's first audio packet was sent

#### Scenario: One shared instant is used

- **WHEN** a group of several members starts
- **THEN** every member reports anchoring its first content sample to the same instant

#### Scenario: The barrier holds a fast member

- **WHEN** one member's setup completes far earlier than the others'
- **THEN** that member sends no content until the barrier releases, and its first sample is still audible at the shared instant

### Requirement: Per-Session Timelines Are Offset

Each member's on-wire timeline MUST be offset per session — its initial sequence number and RTP offset are derived from the session, not from the content or the group — so that two streams from one host carrying the same content are not wire-identical. The offset MUST be carried by that member's anchor so the audible schedule is unchanged.

#### Scenario: Two members are not wire-identical

- **WHEN** two members of one group stream identical content
- **THEN** their packets differ in sequence numbering and RTP offset even where the payload is the same

#### Scenario: The offset is absorbed by the anchor

- **WHEN** two members are compared at the shared instant
- **THEN** each member's anchor line maps the same content sample to that instant despite the different offsets

#### Scenario: Offsets are reproducible prefixes

- **WHEN** the same group start is repeated
- **THEN** each member's offset is derived from the session again, so the offsets differ from the previous run

### Requirement: Group Start Success Is Judged Within A Tolerance

A group start MUST be reported as synchronised only when every member reports its first content sample audible within the group tolerance of the shared instant. The tolerance MUST be 50 milliseconds; a member outside it MUST be reported as out of sync together with the instant it actually used, and MUST NOT be counted as synchronised.

#### Scenario: Members inside the tolerance synchronise

- **WHEN** every member's reported audible instant is within 50 milliseconds of the shared instant
- **THEN** the group reports a synchronised start and reports each member's instant

#### Scenario: A late member is reported out of sync

- **WHEN** one member reports its first sample 120 milliseconds after the shared instant
- **THEN** the group reports that member as out of sync with its actual instant, and does not report the group as synchronised

### Requirement: A Failed Member Does Not Hide The Group Result

When a member cannot bind, cannot be timed, or fails during the start, the group MUST report that member's coded error and MUST report the start as at most partially successful. The remaining members continue to play, and the group MUST NOT be reported as a fully synchronised group.

#### Scenario: An untimed member is reported

- **WHEN** one member's receiver cannot be timed while the others start normally
- **THEN** the group reports that member's coded timing error and the group result as partially successful

#### Scenario: A member that dies mid-start is reported

- **WHEN** a member's session fails between the barrier release and its first packet
- **THEN** the group reports the failure with its member identity and keeps the other members playing

### Requirement: Group Completion Is Reported From Session State

A group MUST report completion when every member's session has reported its content drained or failed, driven by each session's own completion state rather than by polling receivers on an interval. The group MUST NOT depend on a fixed sleep interval to decide that playback finished.

#### Scenario: Completion follows the sessions

- **WHEN** every member's session reports its content drained
- **THEN** the group reports completion without waiting on any interval-based poll

#### Scenario: Completion is not clock-dependent

- **WHEN** the harness holds the injected clock still while every member's content drains
- **THEN** the group still reports completion, so no interval-based wait can be hiding in the path

#### Scenario: A failed member still completes the group

- **WHEN** one member has failed and the rest drain
- **THEN** the group completes and reports the failed member alongside the completion
