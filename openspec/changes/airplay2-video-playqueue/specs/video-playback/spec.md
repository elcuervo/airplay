# Spec Delta

## Purpose

Plays video from a URL or a local file on receivers that no longer accept the deprecated
`POST /play` endpoint, by driving the receiver's own play queue over the authenticated control
channel and reporting what the receiver actually does rather than what the commands implied.

## ADDED Requirements

### Requirement: URL control stream is established before any queue command

On the modern route the sender MUST obtain a URL control stream with `SETUP` — a stream entry of
`type 130` carrying the sender's client UUID, the remote-control client type, the channel
identifier and a control type of 1 — and MUST NOT issue a queue command before the receiver has
acknowledged that stream with a stream identifier.

#### Scenario: Registration precedes commands

- **WHEN** a play is issued on the modern route
- **THEN** the receiver double observes the control-stream `SETUP` before any `POST /command` request, and every command carries the stream identifier the receiver returned

#### Scenario: No stream identifier in the answer

- **WHEN** the receiver answers the control-stream `SETUP` without a stream identifier
- **THEN** the sender raises the protocol failure for the control stream and sends no queue command

### Requirement: Play queue start sequence

Starting playback MUST issue, in order, `insertPlayQueueItem` carrying the item UUID, the media URL
and the start position, then `setProperty` for `isInterestedInDateRange`, then `setProperty` for
`actionAtItemEnd`, then `setRate`, and MUST stop the sequence at the first command whose response
is not a 2xx.

#### Scenario: Start sequence

- **WHEN** a play is issued on the modern route
- **THEN** the receiver double observes exactly those four commands in that order, each decoding to the payload its fixture records

#### Scenario: A failing command ends the sequence

- **WHEN** the receiver answers one of the commands with an error status
- **THEN** no later command of the sequence is observed

### Requirement: Command envelope

Each queue command MUST be a request to `POST /command` with the Apple binary-plist content type, a
body that is a binary plist wrapping the command as a nested binary plist, and the session
identifier plus the stream identifier of the URL control stream.

#### Scenario: Nested plist body

- **WHEN** a queue command is sent
- **THEN** the receiver double decodes the outer binary plist, decodes the command from the nested data member, and both decode without error

#### Scenario: A bare command body fails the test

- **WHEN** a request carries the command as the top-level plist instead of the nested form
- **THEN** the receiver double answers with a client error, so a regression to the bare form cannot pass

### Requirement: Version-sensitive wire values come from a profile

The sender user agent, the protocol version header, the stream-identifier header spelling, the
channel-identifier derivation and the queue command field names MUST come from a per-firmware data
selection rather than from one compiled value, and the selection used for a session MUST be recorded
in the session log.

#### Scenario: The selection decides identification

- **WHEN** a play runs under a selection whose sender version differs from the default's
- **THEN** the requests carry that selection's sender version and header spelling, and the log names the selection

#### Scenario: Unknown firmware

- **WHEN** the receiver's version is not present in the profile table
- **THEN** the default profile is used, the session log records that a default was chosen, and the play proceeds

### Requirement: Start position travels inside the queue item

A requested start position MUST be encoded in the inserted queue item for that item's UUID, in the
position representation the profile's fixture records, and MUST NOT be applied by a follow-up seek.

#### Scenario: Start at an offset

- **WHEN** a play is requested at a non-zero position
- **THEN** the receiver double observes that position inside the inserted item and observes no seek command

### Requirement: Queue manipulation

Adding, removing and selecting the next or previous item MUST be sent as queue commands on the
command endpoint, and MUST NOT use the legacy `/play`, `/rate` or `/scrub` endpoints on the modern
route.

#### Scenario: Add and remove

- **WHEN** the caller appends an item and later removes it
- **THEN** the receiver double observes the queue commands for the caller's item UUIDs and no legacy endpoint request

#### Scenario: Next and previous

- **WHEN** the caller selects the next or the previous item
- **THEN** the receiver double observes a queue selection command for the selected item's UUID and no legacy endpoint request

### Requirement: Pause and resume

On the modern route, pause MUST be sent as a queue-route rate command with rate zero and resume MUST
be sent as the same command with rate one, and neither MUST use the legacy `/rate` endpoint.

#### Scenario: Pause then resume

- **WHEN** the caller pauses and then resumes
- **THEN** the receiver double observes a rate-zero command followed by a rate-one command and no `/rate` request

### Requirement: Stop

Stop MUST end playback on the modern route with the stop sequence the profile records, defaulting to
a rate-zero command followed by removal of the current item, and MUST leave the session usable for a
subsequent play.

#### Scenario: Stopping and playing again

- **WHEN** the caller stops playback and then plays another URL on the same session
- **THEN** the receiver double observes the stop sequence, then a new item insert, and the session is not torn down

### Requirement: Seek

Seeking MUST move the current item's position by a queue-route command carrying the new position for
that item's UUID, and MUST NOT use `GET /scrub` or the legacy `/scrub` endpoint on the modern route.

#### Scenario: Seek within the item

- **WHEN** the caller seeks to a position in the current item
- **THEN** the receiver double observes a command carrying that position for the current item's UUID and no scrub request

### Requirement: Playback rate

A rate other than pause or resume MUST be sent as a queue-route rate command carrying that value,
and the rate the sender reports MUST come from the receiver's reported state rather than from the
value it sent.

#### Scenario: Rate is applied and then reported

- **WHEN** the caller sets a non-unit playback rate
- **THEN** the receiver double observes a rate command with that value, and the reported state carries the rate the receiver reports afterwards

### Requirement: Transient internal errors are retried with a bound

A play whose first queue command fails with the transient receiver `500` MUST be retried, at most
three attempts in total with a one-second pause between attempts, MUST NOT re-insert an item that
was already inserted, and MUST NOT retry any other failure status.

#### Scenario: Transient failure recovers

- **WHEN** the receiver answers the first insert with `500` twice and then accepts it
- **THEN** the play succeeds on the third attempt and the receiver double records exactly three attempts

#### Scenario: Failure after the item was inserted

- **WHEN** a later command of the sequence fails with `500` after the insert was accepted
- **THEN** the failure is reported without a second insert and the receiver double observes exactly one item UUID

### Requirement: Authentication failures map onto the pairing error contract

A `401` on the modern route MUST be reported as the pairing contract's `auth_required` error and a
`403` MUST be reported as `auth_failed`, each carrying its machine-readable code and causing no
retry.

#### Scenario: Challenge

- **WHEN** the receiver answers a queue command with `401`
- **THEN** the caller receives `auth_required` with its code and the double records exactly one attempt

#### Scenario: Refusal

- **WHEN** the receiver answers a queue command with `403`
- **THEN** the caller receives `auth_failed` with its code

### Requirement: The legacy route is chosen from capabilities, not from failure

The route MUST be decided from the device capability model before any command is issued: a receiver
without modern video control support, or one whose firmware is unknown while the conservative policy
is in force, MUST be served by the legacy `POST /play` flow, and the decision with its reason MUST
appear in the session log.

#### Scenario: The capability model says legacy

- **WHEN** a receiver's capability model reports no modern video control support
- **THEN** the sender sends `POST /play` with the media URL and never requests a URL control stream

#### Scenario: Unknown firmware under the conservative policy

- **WHEN** the receiver's version is unknown and the conservative policy is in force
- **THEN** the sender selects the legacy route, records the reason, and sends no queue command

### Requirement: A refused control stream is a typed failure

When the route policy selected the modern route and the receiver refuses the URL control stream, the
sender MUST report a protocol failure naming the receiver's status, MUST send no queue command, and
MUST NOT silently downgrade that session to the legacy route.

#### Scenario: The receiver refuses the control stream

- **WHEN** the receiver answers the control-stream `SETUP` with an error status
- **THEN** the caller receives the protocol failure naming that status and the receiver double observes no `POST /command` request

### Requirement: A play completes on the receiver's reported state

A play MUST NOT be reported successful merely because the commands were accepted: it MUST complete
or fail on the playback state the receiver reports, and a queue-route session MUST NOT treat a
failing `GET /playback-info` as a playback failure.

#### Scenario: Accepted but never playing

- **WHEN** the receiver accepts every queue command and never reports playback starting
- **THEN** the play fails with the playback failure that says playback did not start

#### Scenario: playback-info is not part of a queue session

- **WHEN** the receiver answers `GET /playback-info` with an error status
- **THEN** that answer is ignored as a state source and the session continues until the receiver reports an end
