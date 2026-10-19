# Proposal

## Why

Legacy AirPlay is the compatibility floor this project must not lose. The image (`PUT /photo`
with `X-Apple-Transition`), video (`POST /play` with `Content-Location`) and playback-status
endpoints are the only part of the protocol whose wire contract is already implemented here
and already exercised by real hardware (Apple TV 3, AirPort Express, AirServer,
shairport-sync, UxPlay); they are also the only path available on receivers that never
implement AirPlay 2. The current implementation of that path is dead code for two independent
reasons — it cannot load on a supported Ruby, and its HTTP client is a 2014 HTTP/1.0 socket
hack (`net-ptth`) wrapped in a Celluloid actor. Dropping it would silently narrow the project
to modern Apple devices only, so it must be re-expressed on the new runtime instead of
inherited as baggage.

## What Changes

- Port the AP1/RAOP-compat control plane onto the async session: `GET /server-info`,
  `PUT /photo` (transitions, content length, raw and file inputs), `POST /play` with
  `Content-Location`/`Start-Position`, `POST /rate?value=`, `PUT /setProperty?...`,
  `GET /playback-info`, `GET /scrub`, `POST /stop`, and the legacy `--url` direct-device mode.
- Replace the `net-ptth` persistent-socket trick with an explicit HTTP/1.1 keep-alive client on
  the reactor, including the `User-Agent: MediaControl/1.0`, `X-Apple-Session-ID` and
  `X-Apple-Device-ID` defaults, and the legacy digest-auth shape (RFC 2617, realm `raop`,
  user `iTunes`/`Airplay`) driven from a supplied password.
- Replace the Reel/Cuba/Rack file server with an `async-http` based media server that serves
  local files to the device properly: HTTP/1.1 range requests (206, `Content-Range`),
  correct `Content-Type`/`Content-Length`, HEAD, connection reuse, and a stable URL per file
  for the lifetime of a playback session.
- Keep the useful public model — device, viewer with transitions, player with playlists and
  progress callbacks — but make it reactor-safe: playback state transitions and progress
  reporting no longer rely on polling `sleep` loops inside actors.
- Preserve a documented fallback: when a device advertises AirPlay 2, the route decision
  (`airplay2-pairing-control`) chooses that path, and this legacy path remains available
  explicitly by flag.
- Explicitly not in this change: AirPlay 2 pairing/encryption, the modern play-queue video
  flow, audio streaming, PTP timing, and any change to photo support on AirPlay 2 receivers
  (which remains unverified and is out of scope here).

## Capabilities

### New Capabilities
- `airplay1-control`: the legacy AirPlay control plane — server info, photo push with
  transitions, URL playback, transport commands, playback info/scrub, and digest
  authentication — over the modern async HTTP client.
- `media-serving`: serving local media to a device from the sender, with HTTP/1.1 range
  support, correct metadata and a session-scoped URL contract.

### Modified Capabilities
- `test-harness` (introduced by the sibling change `runtime-async-reset`): grows here through
  an `ADDED` delta in this change's own directory — the legacy receiver mode this change's
  tests run against, its recorded-traffic surface, and its digest challenge control. The
  extension uses `ADDED` requirements under that same capability path with `Legacy ` prefixed
  names, because no base spec exists under `openspec/specs/` until the owning change is
  archived. `service-discovery` and `device-capabilities` (from `mdns-discovery`) are consumed
  by this change, not redefined.

## Impact

- Rewrites `lib/airplay/viewer.rb`, `lib/airplay/playable.rb`, `lib/airplay/player.rb`,
  `lib/airplay/player/media.rb`, `lib/airplay/player/playback_info.rb`,
  `lib/airplay/player/playlist.rb`, `lib/airplay/player/timers.rb`,
  `lib/airplay/server.rb` + `lib/airplay/server/app.rb`, `lib/airplay/connection*`,
  and the `list`/`play`/`view` verbs of `lib/airplay/cli.rb`.
- Removes `net-ptth`, `reel`, `reel-rack`, `cuba`, `micromachine` from the runtime graph; the
  `Keep-Alive`/session behaviour is now explicit and testable.
- Harness slice: the virtual receiver's legacy mode (server-info, photo, play, playback-info,
  digest challenge) plus assertions on range requests, 206 responses, odd MIME types, missing
  files and photo payload integrity.
- Once this lands, the project is usable again on legacy devices even if no modern-receiver
  work had started, which keeps the other four changes independently shippable.
