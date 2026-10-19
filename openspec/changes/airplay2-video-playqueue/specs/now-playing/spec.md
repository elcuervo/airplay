# Spec Delta

## Purpose

Pushes the sender's now-playing state to the receiver so the receiver's own on-screen interface
describes what is playing, with the metadata, artwork, transport controls and playback client the
receiver renders, and so a modern receiver keeps the session alive while the media plays.

## ADDED Requirements

### Requirement: Now-playing is pushed on the encrypted control channel

The sender MUST push now-playing as a command on the session's encrypted control channel, MUST NOT
use the legacy metadata parameter path for it, and MUST NOT push it on a timer.

#### Scenario: The push arrives on the control channel

- **WHEN** playback metadata is set on a modern-route session
- **THEN** the receiver double observes the push on the encrypted control channel and observes no legacy metadata parameter request

#### Scenario: Nothing is pushed without a change

- **WHEN** a session plays with no metadata, artwork or state change for longer than a second-scale polling period
- **THEN** the receiver double observes no further now-playing push

### Requirement: Now-playing envelope

Each push MUST use the MediaRemote now-playing envelope — an update of the now-playing info carrying
the text now-playing parameter wrapper and a merge policy — and MUST NOT send a bare command or an
invented outer message type.

#### Scenario: Envelope shape

- **WHEN** a full now-playing push is sent
- **THEN** the receiver double decodes the documented envelope including the parameter wrapper and merge policy, and no push recorded in the session lacks the wrapper

### Requirement: Now-playing field set

A push MUST carry the item title, artist, album, duration, elapsed time, playback rate, a timestamp as
a date value, the item identifier, and the artwork bytes with their MIME type and artwork identifier,
and MUST omit a field the caller has no value for instead of sending it empty.

#### Scenario: Metadata with artwork

- **WHEN** a title with embedded artwork is set
- **THEN** the receiver double observes every field of that set, with artwork bytes identical to the supplied bytes

#### Scenario: Metadata without artwork

- **WHEN** a title with no artwork is set
- **THEN** the artwork keys are absent from the push rather than present and empty

### Requirement: Supported transport commands are advertised

The sender MUST push, as the receiver's supported command list, the transport commands the receiver
can send it, and MUST re-push that list when the supported set changes.

#### Scenario: The supported set changes

- **WHEN** a transport command becomes available or unavailable on the session
- **THEN** the receiver double observes a new supported-command push whose contents match the newly supported set

### Requirement: Playback state is pushed explicitly

The sender MUST push its playback state explicitly on every start, pause, resume and stop, and MUST
NOT stream progress updates to convey position.

#### Scenario: Transport changes push state

- **WHEN** the caller pauses, resumes and then stops
- **THEN** the receiver double observes one state push per transition and no recurring push while nothing changes

### Requirement: Playback client is identified

The sender MUST push the playback-client representation as part of its now-playing sequence so the
receiver attributes the session to that client.

#### Scenario: Client push

- **WHEN** the initial now-playing sequence for an item is pushed
- **THEN** the receiver double observes the playback-client push and it carries the client identity the double requires

### Requirement: Initial sequence is ordered and serialized

The initial now-playing sequence MUST be pushed in the reference order — now-playing info, then
supported commands, then playback state, then the playback client — and two pushes MUST NOT
interleave.

#### Scenario: Sequence order

- **WHEN** now-playing starts for a new item
- **THEN** the receiver double observes those four pushes in that order

#### Scenario: Concurrent pushes

- **WHEN** two metadata changes are applied at the same time
- **THEN** each push arrives complete and the recorded order is one of the two possible serializations

### Requirement: Full pushes carry artwork bytes

A full now-playing push MUST carry the artwork bytes, MIME type and artwork identifier whenever
artwork is retained for the item, because receivers do not preserve artwork across pushes by
identifier alone.

#### Scenario: Correction after artwork

- **WHEN** a later metadata or state change is pushed for an item whose artwork is retained
- **THEN** the push carries the artwork bytes again and the double reports artwork still available to the receiver

### Requirement: Timeline corrections use the update merge policy

A timeline-only correction — a seek, and the elapsed update that accompanies pause or resume — MUST
use the update merge policy and MUST NOT carry artwork, the pause or resume timeline update MUST be
pushed before its playback-state push, and a stop MUST push state only.

#### Scenario: Seek

- **WHEN** the caller seeks
- **THEN** the receiver double observes an update-form push carrying only timeline fields and no artwork keys

#### Scenario: Pause

- **WHEN** the caller pauses
- **THEN** the receiver double observes the timeline update before the paused state push

#### Scenario: Stop

- **WHEN** the caller stops
- **THEN** the receiver double observes a state push and no timeline push for that stop

### Requirement: Item identity is stable across progress pushes

The item identifier MUST stay the same while the item is unchanged, MUST change when the item
changes, and a push whose entire content equals the last delivered one MUST be suppressed.

#### Scenario: Progress push keeps identity

- **WHEN** only the elapsed time changes for an item
- **THEN** the push reuses the item identifier

#### Scenario: The item changes

- **WHEN** a different item starts playing
- **THEN** the push carries a new item identifier and the previous item's artwork does not ride the new item

#### Scenario: Identical bundle

- **WHEN** the same metadata, artwork and state are pushed again unchanged
- **THEN** no push is recorded for it

### Requirement: A receiver rejecting the update policy gets full pushes

When a receiver answers an update-form now-playing push with a client error, the sender MUST fall back
to full pushes for the remainder of that session and MUST NOT repeat the update form.

#### Scenario: Policy rejected

- **WHEN** the receiver double rejects the update form once
- **THEN** the next timeline correction is sent in the full form and no further update-form push is recorded

### Requirement: Now-playing failures do not fail playback

A client error in response to a now-playing push MUST be recorded with its status and MUST NOT abort
playback, the queue session or the play.

#### Scenario: Push rejected

- **WHEN** the receiver answers a now-playing push with a client error
- **THEN** the failure is recorded, the play continues and the receiver double observes no teardown

### Requirement: Now-playing is gated per receiver and disableable

Now-playing MUST be pushed only on sessions whose receiver takes this path, MUST be disableable by
configuration, and MUST NOT be pushed on the legacy route.

#### Scenario: Legacy route

- **WHEN** a receiver is served by the legacy route
- **THEN** no now-playing push is recorded

#### Scenario: Disabled by configuration

- **WHEN** now-playing is disabled by configuration
- **THEN** no push is recorded even on a modern-route session
