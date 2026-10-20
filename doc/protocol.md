## Video play queue

The modern video route drives the receiver's own play queue over the
authenticated control channel. It is selected from the capability model, never
from a failed request; a receiver without `video_v2` control support, or one
whose firmware is unknown while `configuration.conservative_route` is in force,
stays on the legacy `POST /play` route.

The session log names the decision (`player.route` in `player.decision`) and the
profile selection (`queue.profile`), including the reason a default profile was
chosen.

### URL control stream registration

`POST /setup` carries one stream entry:

| Field         | Value                                      |
|---------------|--------------------------------------------|
| `type`        | `130`                                      |
| `controlType` | `1`                                        |
| `clientUUID`  | the sender's device identifier             |
| `clientType`  | the profile's remote-control client type   |
| `channelID`   | the channel identity the profile selects   |

The receiver answers with a `streams` array whose `type 130` entry carries the
`streamID`. Every queue command afterwards carries it in the profile's stream
header (`x-apple-stream-id` or `x-apple-streamid`). An answer without a
`streamID` raises `:control_stream` carrying the response status, and no queue
command is sent.

The channel identifier is derived, not fixed: profiles with receiver identity
use `/info`'s `deviceid` (or the receiver identity), profiles with sender
identity use the sender's device identifier, so two sessions paired with
different receivers do not present the same identity.

### Session ordering

1. pair-verify
2. `GET /info`
3. session `POST /setup` (identity and timing)
4. `POST /record`
5. URL control stream `POST /setup`
6. queue commands

Receivers drop the connection when a later step is performed early, and when a
feedback request is outstanding while a queue command is issued (feedback is
sequence-matched, commands are not). The sender therefore completes feedback
before issuing a command.

### Command envelope

Each queue command is a `POST /command` whose body is a binary plist:

```ruby
{ "command" => Airplay::Plist::Data.new(Airplay::Plist.dump("type" => name, "params" => params)) }
```

Headers carry `user-agent` (profile sender version), `x-apple-session-id` and the
profile's stream header. A bare body whose top level is the command itself is
refused by the receiver with a client error.

### Profiles

Wire values are profile data pinned by committed fixtures in
`test/fixtures/queue/`, each with its provenance.

| Profile     | Firmware   | Sender             | Stream header        | Channel identity | `actionAtItemEnd` |
|-------------|------------|--------------------|----------------------|------------------|-------------------|
| `tvos-26.5` | `870.14.1` | `AirPlay/870.14.1` | `x-apple-stream-id`  | receiver         | present           |
| `tvos-18.4` | `550.10`   | `AirPlay/550.10`   | `x-apple-stream-id`  | sender           | absent            |
| `default`   | unknown    | `AirPlay/960.13.1` | `x-apple-streamid`   | sender           | present           |

### Start sequence

`insertPlayQueueItem`, then `setProperty` `isInterestedInDateRange`, then
`setProperty` `actionAtItemEnd` when the profile includes it, then `setRate`.
The sequence stops at the first non-2xx response.

`insertPlayQueueItem` parameters:

| Field           | Meaning                                                     |
|-----------------|-------------------------------------------------------------|
| `uuid`          | the item identifier the sender uses for seek, select, remove |
| `url`           | the media URL handed to the receiver                         |
| `mediaType`     | the profile's media kind (`file`)                            |
| `secure`        | whether the URL is TLS-secured                               |
| `startPosition` | the requested start position, omitted when zero              |

A start position travels inside the item; it is never applied by a follow-up
seek. `setProperty` carries `name` and `value`.

For a local file the URL is an absolute URL on the address the receiver can
reach, served for the session's lifetime by the media server with the file's
content type, its length and byte ranges. When no reachable address exists the
play fails with `:unusable_media_address` instead of handing over a loopback URL.
A remote URL is passed through unchanged.

### Queue manipulation and transport

| Verb       | Queue command                                          |
|------------|--------------------------------------------------------|
| add        | `insertPlayQueueItem` (no start position)              |
| play       | `insertPlayQueueItem` with `startPosition`, then rate  |
| pause      | `setRate` with `rate` 0                                |
| resume     | `setRate` with `rate` 1                                |
| rate       | `setRate` with that value                              |
| stop       | `setRate` 0, then `removePlayQueueItem` for the item   |
| seek       | `seekToTime` with the item's `uuid` and `position`     |
| next       | `selectQueueItem` for the next item's `uuid`           |
| previous   | `selectQueueItem` for the previous item's `uuid`       |
| remove     | `removePlayQueueItem` for the item's `uuid`            |

No verb uses the legacy `/play`, `/rate` or `/scrub` endpoints on this route.
Stop leaves the session usable: a later play inserts a new item on the same
paired session.

### Playback state model

`Airplay::Playback::State` is route-independent. Each field is `nil` (unknown)
unless the receiver reported it:

| Field            | Source                                                    |
|------------------|-----------------------------------------------------------|
| `status`         | event `state`, or the polled answer's `rate`/emptiness    |
| `duration`       | event `duration`, or `GET /playback-info` `duration`      |
| `position`       | event `position`/`elapsed`, or `position`                 |
| `rate`           | event `rate`, or `rate`                                   |
| `ready_to_play`  | event `readyToPlay`, or `readyToPlay`                     |
| `stall_count`    | event `stallCount`, or `stallCount`                       |
| `item_id`        | event `uuid`/`itemID`, or `uuid`                          |
| `error_code`     | a reported `error.code` or `errorCode`                    |
| `error_domain`   | a reported `error.domain` or `errorDomain`                |

State comes from receiver reports only; an accepted command never means playing.
A play is started only after an observed `playing` state inside the startup
window; otherwise it fails with `:playback_not_started` and the poll/attempt
count is logged. `playing` followed by `loading` followed by `playing` is one
continuing playback; `stopped` after `playing` ends it. Each distinct change is
delivered once; a repeated report is not a change.

Events are decoded from the encrypted event channel, including a message whose
payload is a binary plist nested inside the `data` member, and every event
request is acknowledged. A message with no decodable payload is ignored and the
channel stays open.

When no event arrives, the sender polls `GET /playback-info` at a bounded
interval and logs the polled source. An empty answer means stopped, and a failing
`/playback-info` answer inside a queue session is not a playback failure. A
reported error object is surfaced with its code and domain.

A snapshot request (`getPlaybackState` with a `requestID`) is correlated by that
identifier: the answer updates the model once and an answer with an unknown
identifier is ignored.

### Now-playing

Four MediaRemote pushes on the encrypted control channel, in this order, once
per item: `updateNowPlayingInfo`, `updateSupportedCommands`,
`updatePlaybackState`, `updatePlaybackClient`. Pushes are serialized so two
changes never interleave.

`updateNowPlayingInfo` parameters: `nowPlayingInfo` with the `text` wrapper
(`title`, `artist`, `album`), `duration`, `elapsed`, `rate`, `timestamp` (a date
value), `uuid`, and for a retained artwork `artwork` bytes, `artworkMimeType`
and `artworkIdentifier`; plus `mergePolicy`.

Policy:

- change-driven only, never on a timer;
- a full push (`mergePolicy` `replace`) carries the artwork bytes again whenever
  artwork is retained, because receivers do not preserve it by identifier;
- a timeline correction (`mergePolicy` `update`) carries only timeline fields and
  no artwork; seek uses it, and pause/resume push the timeline before the state;
- stop pushes state only;
- the item `uuid` is stable across progress and fresh per item;
- an identical push is suppressed;
- a receiver that rejects the update form is downgraded to full pushes for the
  rest of the session.

Now-playing is only pushed on the queue route, can be disabled with
`configuration.now_playing = false` or `--no-now-playing`, and a rejected push is
recorded without failing the play.

### Retry and errors

Only the transient case is retried: the first queue command gets at most three
attempts, one second apart, and only when the receiver answers `500`. Nothing is
retried after the item insert, so a retried start cannot duplicate an item.

| Condition                                | Error                          | Code                    |
|------------------------------------------|--------------------------------|-------------------------|
| `401` on a queue command                 | `Airplay::AuthRequiredError`   | `:auth_required`        |
| `403` on a queue command                 | `Airplay::AuthFailedError`     | `:auth_failed`          |
| any other non-2xx command status         | `Airplay::ProtocolError`       | `:protocol_error`       |
| control stream refused or unregistered   | `Airplay::ProtocolError`       | `:control_stream`       |
| play accepted but never reported playing | `Airplay::PlaybackError`       | `:playback_not_started` |
| local media with no reachable address    | `Airplay::PlaybackError`       | `:unusable_media_address` |
| dropped connection                       | `Airplay::TransportError`      | `:connect_failed`       |
| connection refused                       | `Airplay::TransportError`      | `:connection_refused`   |

Every failure is emitted on the machine-readable status line (`code:` plus its
status when there is one) for both the library and the CLI.

### Findings

- The wire shape moved three times in 2026: `AirPlay/550.10`,
  `AirPlay/870.14.1` and `AirPlay/960.13.1`, with both `x-apple-stream-id` and
  `x-apple-streamid` spellings observed. The fixtures record one shape per
  firmware.
- The tvOS 26.5 branch validated with an NTP-timed session; one account reports
  events only on a PTP-timed video session. The hardware lane records the
  negotiated timing mode and the event count per scenario so a mode with no
  events is visible.
- Some receivers ignore now-playing without the MRP origin registration this
  change does not implement; the hardware lane records whether now-playing was
  pushed and leaves the rendering observation explicit.
- `GET /playback-info` errors inside a queue session; treating that error as a
  playback failure is what tore the picture down upstream. The lane records its
  status, and a successful answer is committed as a fixture with its provenance.

Fixtures: `test/fixtures/queue/<profile>.json` carries the commands and its
provenance (reference implementation and firmware), and
`test/fixtures/queue/insert.bplist` is the committed insert body.
