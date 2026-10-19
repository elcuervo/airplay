# Tasks

## 1. Harness: play-queue receiver mode, scripts and fixtures

- [ ] 1.1 Extend the dev-only fake-device package with a play-queue receiver mode that pairs, accepts the encrypted control channel and records every request in arrival order with method, path, headers and decoded binary-plist body; verify a `test:protocol`-lane smoke test starts the mode in-process, drives a control-stream `SETUP` and a `POST /command`, and reads both back from the recorded exchanges
- [ ] 1.2 Add expectation lists to the mode: an ordered list of expected requests compared on method, path, headers and decoded payload, failing at the first divergence and reporting requests that were not expected; verify a deliberately out-of-order test fails naming the differing request while the in-order test passes
- [ ] 1.3 Make the mode answer a command request whose body is not the nested binary-plist form with a client error; verify the bare-form test fails and the nested-form test passes
- [ ] 1.4 Add scripted event-channel transitions triggered on demand from a test (`playing`→`loading`→`playing`, →`paused`, →`stopped`, and a mode that never transitions) plus scripted `playback-info` answers (playing, empty, error); verify one test per script observes the sender reacting to exactly that script
- [ ] 1.5 Add this route's fault knobs — transient `500` on a chosen command index, `401`, `403`, control-stream refusal, a failure after the item was inserted, a connection drop when setup ordering is violated or feedback overlaps a command, and a delayed or absent event answer; verify one test per knob and that the partial-application knob records exactly one item insert
- [ ] 1.6 Commit `test/fixtures/queue/` fixtures captured from the reference implementations per firmware profile, each with a provenance note naming the reference and the firmware it came from; verify a test loads a fixture, asserts its provenance is present and decodes its nested payload
- [ ] 1.7 Add the mode's media-fetch client, which fetches a URL the sender handed it — including a byte range — and records the requests it made and the responses it received; verify a test drives a local-file play and asserts the served content type, length and partial-content answer from the recorded fetch

## 2. Control-stream setup

- [ ] 2.1 Implement URL control stream registration on the session (`SETUP` with a `type 130` entry carrying the client UUID, remote-control client type, channel identifier and control type 1) and expose the stream identifier the receiver returns; verify the protocol-lane test matches the request against its profile fixture and that an answer without a stream identifier raises the control-stream protocol failure
- [ ] 2.2 Implement the channel-identity derivation the selected profile records (receiver-reported identity or sender address) so identifiers are not fixed values; verify a test pairing with two receivers records two different channel identifiers
- [ ] 2.3 Implement the session ordering — pairing verification, then the receiver's information, then session `SETUP`, then the record request, then the control stream — and the rule that no feedback request is outstanding when a queue command is issued; verify the ordering and overlapping-feedback fault knobs both report the connection failure
- [ ] 2.4 Implement profile selection from the firmware the receiver reports, with the default profile and a logged reason for an unknown version; verify a unit test covers a known version, an unknown version and the logged reason
- [ ] 2.5 Document the registration in a new `doc/protocol.md`, wired into `doc/toc.md` and the README structure list in `Rakefile`; verify `rake doc:generate` emits the section and the documented field names match the fixture

## 3. Queue command client

- [ ] 3.1 Implement the command request — `POST /command` with the nested binary-plist body and the session and stream identifiers, using the profile's identification values; verify the mode decodes the nested payload and asserts the headers from the fixture
- [ ] 3.2 Implement `insertPlayQueueItem` with the item UUID, media URL, media kind, transport-security flag and start position; verify the mode observes each of those values and, for a positioned start, records no seek command
- [ ] 3.3 Implement the ordered start sequence (insert, `isInterestedInDateRange`, `actionAtItemEnd`, `setRate`) with fail-fast on the first non-2xx response; verify the expectation-list test passes and one injected failure per command index stops the sequence at that point
- [ ] 3.4 Implement queue manipulation (add, remove, next, previous) on the command endpoint; verify the mode observes the queue commands for the caller's item UUIDs and records no legacy endpoint request
- [ ] 3.5 Put the documented firmware variants' differences (sender version, stream-identifier header spelling, channel-identity derivation, presence of `actionAtItemEnd`) behind the profile seam; verify replaying each profile's fixture passes with no code change

## 4. Playback-state model

- [ ] 4.1 Implement the route-independent model — status, duration, position, rate, ready and stall hints, item identifier, receiver error code and domain, unknown for unreported fields, and one delivery per change; verify unit tests for field presence, unknown-not-zero, duplicate suppression and error passthrough
- [ ] 4.2 Implement the event adapter (decode event plists including the nested data member, handle playback-state and notification messages, normalize states); verify protocol-lane tests for `playing`→`loading`→`playing`, →`paused` and →`stopped`
- [ ] 4.3 Implement the startup rule — started only on an observed `playing` transition inside the bounded window, otherwise the did-not-start failure; verify the never-transitioning mode produces that failure and records the attempt count
- [ ] 4.4 Implement the polled adapter over `GET /playback-info` (bounded interval, empty answer means stopped, reported error object surfaced) selected only when no event arrives; verify tests for a silent receiver starting and ending, an empty answer, an error answer, and a failing playback-info inside a queue session not being a state failure
- [ ] 4.5 Implement snapshot requests with request-identifier correlation and the rule that an unmatched answer is ignored; verify one test per case and that a correlated answer updates the model once
- [ ] 4.6 Route the legacy video session and the audio session through the same model; verify the shared state assertions pass identically for an event-driven and a polled session, and that the audio case is driven from `raop-audio-stream`'s session double
- [ ] 4.7 Document the model in `doc/protocol.md` (each field with its source and the fallback rule); verify every documented field is exercised by a named test

## 5. Transport verbs

- [ ] 5.1 Implement pause and resume as queue-route rate commands; verify the mode observes rate zero followed by rate one and no `/rate` request
- [ ] 5.2 Implement stop as the profile's sequence, defaulting to rate zero followed by removal of the current item; verify the mode observes it and that a subsequent play on the same session inserts a new item without re-pairing
- [ ] 5.3 Implement seek as a queue command carrying the position for the current item's UUID; verify the mode observes the position, records no scrub request, and that the reported position follows the receiver's state rather than the requested value
- [ ] 5.4 Implement non-unit playback rate; verify the mode observes the value sent and that the reported rate is the one the receiver reports afterwards
- [ ] 5.5 Put every verb on the shared playback interface so callers never branch on route; verify a unit test drives each verb through both route implementations and observes queue commands on one and legacy endpoints on the other
- [ ] 5.6 Document each verb's queue-route mapping next to the fixture that pins it in `doc/protocol.md`; verify every documented mapping matches the recorded request

## 6. Now-playing

- [ ] 6.1 Implement the now-playing envelope and the four initial pushes (now-playing info with the text parameter wrapper, supported commands, playback state, playback client) with serialized sending; verify the mode asserts each decoded shape, the order between them and that two concurrent pushes arrive complete
- [ ] 6.2 Implement the field set including artwork bytes, MIME type and artwork identifier, a timestamp sent as a date value, and omission of fields the caller has no value for; verify fixtures with and without artwork
- [ ] 6.3 Implement the change policy — change-driven only, timeline corrections in the update form with pause/resume pushing the timeline before the state, artwork on every full push, an identical bundle suppressed, the item identifier stable across progress and fresh per item, and a rejected update form downgrading the session to full pushes; verify one test per rule by counting the pushes recorded in the mode
- [ ] 6.4 Implement gating: modern route only, a configuration switch, and a client error recorded without failing the play; verify tests for a legacy-route session recording no push, a disabled session recording no push, and an injected client error during playback leaving the play running
- [ ] 6.5 Document the envelope, field set, policy and gating in `doc/protocol.md`; verify each documented rule is named by a test

## 7. Retry and error contract

- [ ] 7.1 Implement the bounded retry — the first queue command only, at most three attempts one second apart — and its exclusion once the item was inserted; verify the `500`, `500`, accept script succeeds on the third attempt and the after-insert failure script records no second insert
- [ ] 7.2 Implement status mapping: `401` to `auth_required`, `403` to `auth_failed`, any other non-2xx to a typed protocol failure carrying its status, with none of them retried; verify one test per mapping
- [ ] 7.3 Implement the refused-control-stream path as a typed failure naming the receiver's status with no queue command and no downgrade to the legacy route; verify the refusal knob records no `POST /command` request
- [ ] 7.4 Emit every failure on the machine-readable status line for both the library and CLI paths; verify a test table covers auth required, auth failed, did-not-start, protocol refusal and connection failure with their codes
- [ ] 7.5 Document the route, retry and error matrix in `doc/protocol.md`; verify each row of the matrix is exercised by a named test

## 8. Opt-in hardware lane

- [ ] 8.1 Add the three media scenarios (remote HLS, locally served HLS, locally served progressive file) to the hardware lane, gated by environment configuration; verify the lane skips with a reason and exits successfully with nothing configured
- [ ] 8.2 Record per run and per scenario the device model, firmware version, timing mode, profile used, observed state sequence, event count and outcome; verify a run's output contains each of those fields
- [ ] 8.3 Add the route comparison (modern route, then the legacy route forced on the same device) and the now-playing observation (whether the receiver renders title and artwork without an origin registration); verify both are recorded with their outcome instead of being silently skipped
- [ ] 8.4 Record the timing mode the session negotiated and its event count per scenario; verify the output names the mode and the count, so a mode with no events is visible
- [ ] 8.5 Record the status `GET /playback-info` returned during a queue-route run and, when a receiver answers it successfully there, commit that answer as a fixture with its provenance; verify the run output names the status and the committed fixture carries the capture's device and firmware

## 9. CLI wiring

- [ ] 9.1 Replace the `play` verb's flow with the session-based one (resolve the device, select the route, hand the media to the route, wait on the state model); verify CLI-level tests play a remote URL and a local file against the queue mode and against the legacy mode
- [ ] 9.2 Drive the progress display from the state model instead of polling; verify scripted receiver transitions move the display and a unit test shows no polling loop or sleep remains in the CLI
- [ ] 9.3 Add the transport verbs (pause, resume, stop, seek, next, previous, rate) to the CLI dispatch through the shared playback interface; verify each verb against the queue mode and that no legacy endpoint request appears on a queue route
- [ ] 9.4 Show the route decision, the firmware and the profile with the reason in the human status output; verify the output names them for a modern receiver, a legacy receiver and a receiver whose firmware is unknown
- [ ] 9.5 Add the options that force the legacy route and disable now-playing; verify a test compares the CLI's help output with the options the parser accepts, so no option is undocumented or phantom
- [ ] 9.6 Keep the legacy receiver's experience unchanged end to end (play, pause, resume, stop, progress) with a CLI test against the legacy mode; verify the legacy lane stays green

## 10. Documentation and findings

- [ ] 10.1 Update `doc/usage.md` for the new verbs, options and route status output; verify the documented examples match the CLI's help output and the lane's status lines
- [ ] 10.2 Add the firmware and profile findings to `doc/protocol.md` — the profile table, the points on which the reference shapes disagreed, the timing-mode observation and the now-playing rendering observation — each naming the run or fixture it came from; verify every finding names one
- [ ] 10.3 Regenerate the README with `rake doc:generate`; verify the new page appears in the generated README and its table-of-contents entry resolves
- [ ] 10.4 Verify the change's documentation claims against the fixtures: no documented header, field name or command name lacks a fixture or a captured run; fix the gap or record it as a finding in 10.2

## Workflow follow-up

- Archive `airplay2-pairing-control` before this change: it owns `airplay2-control-channel`, and this delta is `ADDED` because no base spec exists under `openspec/specs/` until that change is archived.
- Archive `airplay1-legacy-sender` before this change: it owns `media-serving`, for the same reason.
- Archive `runtime-async-reset` before this change: it owns `test-harness`, whose play-queue mode this change's delta extends.
- `playback-state` is created by this change and consumed by `raop-audio-stream`; archive this change before any later delta that extends it.
- Keep the profile table and `test/fixtures/queue/` in step: a new firmware capture means a fixture, a profile entry and a provenance note, and the hardware lane's per-run recordings are the input to that work.
