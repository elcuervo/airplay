# Design

## Context

The legacy plane already exists in this repository and is the only part of the wire contract
this project has verified against hardware; see `proposal.md` for why it must be re-expressed
rather than dropped. What shapes the approach is the shape of the old code:

- `lib/airplay/connection/persistent.rb` fakes persistence with `net-ptth` 0.0.17 (2014):
  HTTP/1.0 requests over a socket that is never re-established, no timeouts, no streaming
  bodies. `Airplay::Connection` is a Celluloid actor that wraps it and returns
  `Response = Struct.new(:connection, :response)`; `lib/airplay/player.rb` keeps a *second*
  connection object purely because the first one's socket is unreliable for playback.
- `lib/airplay/connection/authentication.rb` signs a request with `net-http-digest-auth` after
  issuing it unauthenticated once to harvest the challenge, and hard-codes the digest username
  `Airplay`.
- `lib/airplay/server.rb` boots Reel through `Rack::Server`; `lib/airplay/server/app.rb` is a
  Cuba app mapping `/assets/:uuid` onto `Rack::File`, with a process-global `Hash` (default
  proc) mapping file path → UUID. Readiness is polled with `sleep 0.1 until running?`, and the
  free port is found by opening and closing a listener.
- `lib/airplay/player.rb` drives a `micromachine` FSM from a one-second Celluloid timer that
  polls `/playback-info`; `wait` is `sleep 1 while wait_for_playback?`; `progress` registers a
  `Timers#every(1)` callback per subscriber, so each subscriber adds its own poll; the
  "played" state is detected by `info.keys.size == 2`.
- `lib/airplay/viewer.rb` resolves the four accepted picture inputs, reading files with
  `File.read` (encoding-sensitive) and fetching URLs with `open-uri`; `File.exists?` is gone on
  Ruby 3.4, so none of it loads.
- The wire contract the old code implements is the AirPlay HTTP API (`GET /server-info`,
  `PUT /photo`, `POST /play`, `POST /rate`, `POST /scrub`, `GET /scrub`, `GET /playback-info`,
  `PUT /setProperty`, `POST /stop`), with `User-Agent: MediaControl/1.0`,
  `X-Apple-Session-ID`, `X-Apple-Device-ID`, and digest challenges whose realms are `raop`
  (RTSP side, username `iTunes`) and `AirPlay` (HTTP side).

`runtime-async-reset` supplies the pieces this change builds on: `Airplay::Session.open`, the
error taxonomy with machine-readable codes, the plist baseline (XML and binary), the in-process
harness tiers and an injectable clock. `mdns-discovery` supplies the structured device records
and the address to advertise to a given receiver. `airplay2-pairing-control` owns the route
decision this change plugs into, and `airplay2-video-playqueue` extends the media-serving
contract later.

## Goals / Non-Goals

**Goals:**

- Re-express the legacy control plane and the media server on the async session, keeping the
  publicly documented commands (`list`, `play`, `view`, transitions, playlist, progress) and
  every endpoint the current code uses.
- Make the transport behaviour that used to be implicit explicit and testable: one keep-alive
  HTTP/1.1 connection per session, session identity headers, digest challenge handling with the
  realm-driven username, and a distinction between "password required" and "password wrong".
- Give serving a byte-range contract (206/`Content-Range`/416/`HEAD`), a URL lifetime that
  outlives playback, and bounded reads.
- Delete the old stack (`net-ptth`, Celluloid connection actors, Reel/Rack/Cuba server,
  `micromachine`, Celluloid timers, `open-uri`) with no compatibility shims and no
  re-exported old names.
- Keep the legacy plane a *route*, so a device that advertises AirPlay 2 is handled by
  `airplay2-pairing-control`'s path and the legacy plane remains reachable by explicit request.

**Non-Goals:**

- AirPlay 2 pairing, encryption, play queue, now-playing metadata, audio streaming, screen
  mirroring and PTP timing.
- Verifying or changing photo behaviour on AirPlay 2 receivers: this change implements the
  legacy `PUT /photo` endpoint only.
- Transport security for the media server (no TLS, no authentication of the URL beyond its
  unguessable identifier), which matches the current behaviour and the local-network threat
  model.
- Changing the CLI verb set or output format beyond what the new API forces.
- Reproducing device quirks that neither the harness nor the opt-in hardware lane can observe.

## Decisions

### One keep-alive HTTP/1.1 connection per session, built on `async-http`

Each session owns a single HTTP/1.1 client bound to one origin and one connection, with
`User-Agent: MediaControl/1.0`, `X-Apple-Session-ID` and `X-Apple-Device-ID` applied to every
request. The command layer is a thin map of the endpoints onto that client.

*Why:* the whole legacy control plane is small requests to one origin, and `async-http` is
already required for the media server, so there is one HTTP stack to reason about, with
reactor-native suspension, streaming bodies, timeouts and a real keep-alive implementation.
*Alternatives:* keep `net-ptth` — HTTP/1.0, unmaintained since 2014, no timeouts, and its
"persistent socket" is exactly the hack being removed; hand-roll HTTP/1.1 on `Async::IO` —
maximum control of the bytes, but we would own chunked bodies, no-body responses, keep-alive
and half-close handling forever; stdlib `Net::HTTP` — correct and reusing, but blocking, so it
needs a thread per session and a hand-off back into the reactor for progress, media serving and
cancellation; `http.rb`/Faraday — an extra layer with no reactor integration.

### Digest authentication is a single replay at the command layer

A `401` with a `WWW-Authenticate: Digest` challenge is answered by replaying the same request
once with an `Authorization: Digest` header computed from the challenged realm and nonce, the
request's own method and target, and the session's password. The username is `iTunes` for realm
`raop` and `Airplay` otherwise, overridable per session.

*Why:* the computation is a pure function that needs no HTTP library, one replay is what the
wire contract shows, and the realm is what decides the username — hard-coding it is the reason
the old code failed against RAOP-era receivers.
*Alternatives:* keep the old shape, which sends the request unauthenticated first to harvest a
challenge even when the password is already known (it doubles traffic on success paths and
hides the difference between "no password" and "wrong password"); always `Airplay` — Apple's own
example for the HTTP side uses `AirPlay`, and RAOP expects `iTunes`, so a constant cannot be
right for both; try `iTunes` then `Airplay` — a second wrong attempt against a receiver that
rate-limits or wedges its state machine is worse than a clear failure; an RTSP/digest library —
the RAOP RTSP client is `raop-audio-stream`'s concern, not this change's.

### `Async::HTTP::Server` with an explicit router instead of Rack/Reel/Cuba

The media server is an `Async::HTTP::Server` on the session's reactor with a router that
handles `GET`/`HEAD` on published identifiers, and decides the three outcomes (`200`, `206`,
`416`) plus `404` for everything else.

*Why:* one route with byte ranges, `HEAD` and no-body responses needs no middleware stack, and
running the listener on the same reactor as the control client is what makes concurrent serving
and controlling true without a second thread. Reel and Cuba are in the removal list anyway.
*Alternatives:* Rack on Falcon — Rack is maintained, but this buys a Rack env translation,
a middleware chain and a second server stack for one route; keep Reel + `Rack::File` — the
`Rack::File` body does ranges, but Reel's reactor is Celluloid's and the whole stack is
unmaintained; serve media from a shelled-out server (`python -m http.server`) — unacceptable
dependency and no control over the URL contract; `Async::HTTP::Server` behind a Rack adapter —
reintroduces the cost without any gain.

### Playback state as a declared transition table, not a gem

The five states (`loading`, `playing`, `paused`, `stopped`, `played`) and their legal
transitions live as data in one object with a `handle(snapshot)` step, driven by the session's
sampling task. Side effects the old FSM ran from callbacks (releasing the media URL, advancing
the playlist on completion) are explicit steps of that object.

*Why:* the FSM's whole job is mapping polled `/playback-info` snapshots onto states; as data it
is testable without a reactor or a device, and the transitions the old code left implicit
become checkable requirements.
*Alternatives:* keep `micromachine` — unmaintained, callback-oriented, and it was being mutated
from a timer thread inside a Celluloid actor; a general FSM gem (`state_machines`) — a large
dependency for five states; ad-hoc booleans — the previous code had both, and the booleans are
what made "played" depend on how many keys the receiver happened to report.

### Progress is one sampler and per-subscriber queues

The session runs a single sampling task that reads `/playback-info` at the requested interval,
measuring the interval from *completion*, skipping a tick while a read is outstanding, and
publishing each snapshot to every subscriber's queue. A `progress` call hands the caller an
async enumerable/subscription in the session's task tree; the subscription ends with the
session.

*Why:* the device must not see one poll per subscriber, callbacks must not run on a foreign
thread, and a slow receiver must not accumulate overlapping requests. Deliveries are driven by
the reactor's timers, so the injectable clock makes them exactly testable.
*Alternatives:* the old `Timers#every(1)` — one timer per subscriber, invoked from Celluloid's
timer thread; a `Thread` + `sleep` sampler — off-reactor, unstructured cancellation; the event
channel — owned by `airplay2-pairing-control` and unavailable on the receivers this change
targets; measuring from request start — overlaps on a receiver slower than the interval.

### The media URL is bound to the session, and its host is chosen for the receiver

Publishing a file returns an absolute URL whose host is the address selected for that receiver
(discovery/config), whose port is the *actual* bound port (configured, else OS-assigned), and
whose path is an opaque per-session identifier. The mapping is stable for the session and
revoked when it closes.

*Why:* the receiver, not the sender, fetches the URL, so the advertised address has to be the
one that route reaches; reading the bound port back from the socket avoids the old
open-and-close race; a session-scoped identifier means a released session cannot leak files and
a late fetch after playback still works.
*Alternatives:* keep the process-global file → UUID map (URLs outlive the session and are never
revocable); pick the port by opening and closing a listener (races with the real bind); bind
`0.0.0.0` and advertise the first private IPv4 address (wrong on multi-homed hosts, and it is
what the old `private_ip` did); advertise the local address of the control connection as the
primary source — adopted as the *fallback* when no address is configured, because it is the
interface the receiver is actually reachable on.

### Reconnect for idempotent reads only

If the connection is gone before a response is complete, the sender reconnects and replays
`GET /server-info`, `GET /playback-info` and `GET /scrub`. Playback commands (`/play`,
`/rate`, `/stop`, `/scrub?position`, `/setProperty`, `/photo`) are never replayed on a transport
failure; they surface a connection-category error.

*Why:* receivers close idle keep-alive sockets constantly, which would otherwise show up as
spurious failures on the next read; and replaying a `/play` can start playback twice or skip a
`/stop`, which no device-side signal can disambiguate.
*Alternatives:* replay everything once (silently duplicates playback); never replay (spurious
failures on healthy sessions); a new connection per request (throws away the keep-alive
behaviour the old code went out of its way to obtain, and the session identity headers make it
worthless anyway).

### Plists come from the runtime baseline, with content sniffing on responses

XML plists are decoded for `/server-info` and `/playback-info`; the `/setProperty` body is
encoded as a binary plist and its answer decoded from either representation based on the
`bplist00` magic rather than on `Content-Type`.

*Why:* receivers answer these endpoints with inconsistent `Content-Type` values, and
`/setProperty`'s answer is documented as a binary plist carrying `errorCode` — the spec
requires surfacing that code, so the body has to be parsed.
*Alternatives:* depend on `plist-codec` from `airplay2-pairing-control` — would make this change
unshippable before the modern-receiver work, contradicting the proposal's independence claim;
hand-rolled XML parsing — needless; treat the answer as opaque — loses the error code.

### Photo inputs keep the documented resolution order, with binary-safe reads

The four accepted kinds (raw binary string, existing file path, URL, object responding to
`read`) and their order are preserved; files are read in binary mode, URLs are fetched through
the session's HTTP client, and any other argument fails before a request is issued.

*Why:* this is documented public behaviour (`README.md`, `doc/usage.md`), and the old
implementation's `File.read`/`open-uri` combination is where encoding assumptions crept in;
fetching through the session client keeps the reactor unblocked and gives the fetch the
session's timeouts and error taxonomy.
*Alternatives:* keep `open-uri` — blocks the reactor and `Kernel#open` is gone in Ruby 3.x;
require callers to pass bytes — breaks the documented surface; sniff content by magic bytes and
refuse unknown formats — narrows what the tool sends based on a guess the receiver should make.

### `/play` keeps the `text/parameters` body

`POST /play` sends `Content-Type: text/parameters` with CRLF-separated `Content-Location` and
`Start-Position` lines, and `Start-Position` is the relative fraction in `[0, 1]`.

*Why:* it is the shape this project has always sent and the one its known-good receivers
accept; the reference's alternative XML plist body is the iPhone path and adds a second encoder
with no device to validate it against.
*Alternatives:* XML plist body (documented, but untestable here); binary plist body — that is
the modern `/command` flow owned by `airplay2-video-playqueue`; query-parameter form — not part
of the endpoint.

### Media compatibility stays an inspection, not a gate

The MIME compatibility check stays on the public surface and is backed by the same type table
the media server uses for `Content-Type`, but playback is never refused because of it.

*Why:* a receiver can play things this table does not list, and the device's own fetch is the
authority; gating locally silently narrows the tool.
*Alternatives:* refuse incompatible types locally (untestable without hardware and wrong for
progressive download of unusual containers); delete the check (loses a documented API).

### The legacy plane is selected, never guessed

The session's control plane is chosen by the route the session was opened with (or by an
explicit override); when the device advertises AirPlay 2 the default route is not legacy, and a
legacy failure is reported as a failure with no automatic cross-route retry.

*Why:* `airplay2-pairing-control` owns the capability/credential-driven route decision, and the
sibling change explicitly selects by route rather than by failure — retrying on the modern path
after a legacy `500` would duplicate that policy and could leave the receiver's state machine
wedged.
*Alternatives:* legacy first, modern on failure; modern first, legacy on failure; local
re-implementation of the capability check — three ways to make two components own one decision.

### One session is one task tree

Control client, media server, sampler and progress subscriptions are sibling tasks under the
session; closing the session cancels the tree, closes the socket and unbinds the listener. No
threads, no actor mailboxes, no `sleep` loops: `wait` awaits the playback-state task and
`progress` returns a subscription.

*Why:* structured cancellation is what makes "the URL stops working when the session ends" and
"the socket is closed on teardown" observable rather than best-effort.
*Alternatives:* one thread per session (the Celluloid model being deleted); a process-wide
connection pool shared by sessions — per-session identity headers make pooling across sessions
meaningless and would mix `X-Apple-Session-ID` values.

## Risks / Trade-offs

- [The reference documents `Start-Position` as a fraction and `/scrub?position` as seconds, but
  receivers differ] → the required encodings are exactly those two; the virtual receiver asserts
  them byte-for-byte and the opt-in hardware lane records what a real receiver reports back, so
  a device-specific note can be added without changing the specs.
- [Current firmware answers legacy `POST /play` with `500`] → route selection keeps the legacy
  plane off by default for AirPlay 2 devices, and the failure surfaces as a playback error
  carrying the status rather than a retry or a silent reroute.
- [Digest realm, `qop` and username vary between receivers] → the username follows the
  challenged realm with a session override, and the harness's digest mode parametrises realm,
  nonce, `qop` and username so a new variant is a fixture rather than a code branch.
- [A receiver fetches the media URL lazily, repeatedly, or after playback ends] → URLs stay
  stable and servable for the whole session, and only closing the session revokes them.
- [The advertised host is wrong on multi-homed or containerised hosts] → the address resolved
  for the receiver wins, the control connection's local address is the fallback, and `--url`
  mode skips discovery entirely.
- [Keep-alive sockets are closed by the peer] → transparent reconnect for idempotent reads, no
  replay for playback commands, and harness knobs (close-after-response, `Connection: close`,
  delayed body) so both paths are exercised.
- [Range handling is subtle for empty files, suffix ranges and ranges past EOF] → the three
  outcomes with their exact `Content-Range` values are enumerated in the spec and tested against
  fixtures, including a zero-byte file.
- [Serving a video could read the whole file per request] → file-backed bodies carry an explicit
  offset and length, and the protocol lane asserts through an instrumented handle that no more
  than the requested bytes are read.
- [A second `/playback-info` poll overlapping a slow one] → the interval is measured from
  completion and a tick is skipped while a read is outstanding, keeping control traffic bounded
  regardless of the receiver's speed.
- [The old `played` heuristic (`info.keys.size == 2`) is not reproducible] → the state model
  reads only receiver-reported `rate`/`duration`/`position`, the completion predicate is explicit
  and unit-tested, and the harness carries fixtures for the "empty document", "rate only" and
  "position reached duration" shapes.
- [Credential leakage while old and new code coexist] → the old connection/authentication files
  are deleted in the same change, the client never logs headers it did not construct, and a test
  captures the session's log output while a password is configured.
