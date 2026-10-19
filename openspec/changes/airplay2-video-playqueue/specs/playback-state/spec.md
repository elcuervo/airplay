# Spec Delta

## Purpose

Reports what the receiver is actually doing — status, position, duration, rate, ready and stall
hints, and failures with their receiver-reported codes — from one model shared by the video
play-queue route, the legacy polled route and audio playback.

## ADDED Requirements

### Requirement: State is derived from receiver reports

The sender's playback state MUST be derived from messages the receiver sends on the encrypted event
channel and from its answers to playback-info requests, and MUST NOT be inferred from the fact that
a command was accepted.

#### Scenario: Commands accepted, state unchanged

- **WHEN** a receiver accepts every command of a play and reports only a paused state afterwards
- **THEN** the reported state is paused and never playing

### Requirement: Playing requires an observed start transition

Playback MUST be reported as started only after the receiver reports a playing state, and a play
whose receiver reports no playing state within the bounded startup window MUST fail with the
playback failure that says playback did not start.

#### Scenario: A receiver that never transitions

- **WHEN** the receiver double accepts the commands and never sends a state event
- **THEN** the play fails after the bounded window with the did-not-start failure and the attempt count is recorded

#### Scenario: Normal start

- **WHEN** the receiver reports playing inside the startup window
- **THEN** the play is reported as started at that transition

### Requirement: A replacement is not an end

A sequence in which the receiver reports playing, then an intermediate loading state, then playing
again MUST be treated as one continuing playback, and only a transition to stopped or idle after
playing MUST be treated as the end of media.

#### Scenario: Replacement

- **WHEN** the receiver reports playing, then loading, then playing
- **THEN** the state stays playing throughout and the play is not reported as ended

#### Scenario: End of media

- **WHEN** the receiver reports playing and later reports stopped
- **THEN** the play is reported as ended with the position the receiver last reported

### Requirement: Reported model

The model MUST expose the playback status, duration, position, playback rate, the receiver's
ready-to-play and stall hints and its item identifier whenever the receiver reports them, and MUST
report a field the receiver did not report as unknown rather than as zero.

#### Scenario: Full report

- **WHEN** the receiver reports duration, position, rate, ready, stall and item identifier
- **THEN** each of those values is readable from the model

#### Scenario: Missing field

- **WHEN** the receiver reports a state without a duration
- **THEN** duration is unknown and no arithmetic on it yields zero

### Requirement: Receiver errors are surfaced with their code and domain

An error the receiver reports MUST be surfaced as a playback failure naming the receiver's error code
and error domain, and MUST NOT be flattened into a generic failure.

#### Scenario: Error object

- **WHEN** the receiver reports an error with a code and a domain
- **THEN** the failure carries both values verbatim and the machine-readable playback code

### Requirement: Polling is the fallback state source

When the receiver sends no state on the event channel, the sender MUST fall back to polling
playback-info at a bounded interval and MUST derive the same model from its answers, and the source
in use MUST be observable in the session log.

#### Scenario: Silent receiver

- **WHEN** the receiver double pushes no state and answers playback-info with a playing state followed by an empty answer
- **THEN** the play is reported as started and then ended, and the log names the polled source

#### Scenario: Empty answer means stopped

- **WHEN** playback-info answers with no content
- **THEN** the state is stopped rather than unknown

### Requirement: State snapshots can be requested by identifier

The sender MUST be able to request a playback snapshot over the control channel and correlate the
receiver's answer by the request identifier it sent, and MUST ignore an answer whose identifier
matches no outstanding request.

#### Scenario: Correlated answer

- **WHEN** a snapshot is requested and the receiver answers with the same identifier
- **THEN** that answer updates the model once

#### Scenario: Unknown identifier

- **WHEN** an answer arrives with an identifier that matches no outstanding request
- **THEN** it is ignored and the model is unchanged

### Requirement: One model for every route

The model MUST be independent of the protocol route: queue-route sessions, legacy polled sessions and
audio streaming sessions MUST expose the same fields with the same meanings, and consumers MUST NOT
need to know which route produced a state.

#### Scenario: Equal results across routes

- **WHEN** the same scripted playback is driven through the event route and through the polled route
- **THEN** both produce equal model values and the same transition sequence

#### Scenario: Audio reuses the model

- **WHEN** the audio streaming route reports state
- **THEN** it delivers the same model type with the same field semantics as the video routes

### Requirement: Each change is delivered once

Each distinct state change MUST be delivered to observers exactly once, and a repeated report of the
state that is already current MUST NOT produce another delivery.

#### Scenario: Repeated reports

- **WHEN** the receiver reports the same playing state three times in a row
- **THEN** observers receive one start notification
