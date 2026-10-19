# Pairing flows

Pairing messages are TLV8: one-byte type, one-byte length, then that many value
bytes. Values longer than 255 bytes travel as consecutive same-type items and are
concatenated on decode.

The sender selects the flow with the `X-Apple-HKP` header on every
`POST /pair-setup` request; the receiver does not choose it.

| Header | Flow       | Client messages | Requests | Code         |
| ------ | ---------- | --------------- | -------- | ------------ |
| `4`    | transient  | 4               | 2        | fixed `3939` |
| `3`    | PIN        | 6               | 3        | supplied     |
| —      | pair-verify| 4               | 2        | —            |

## Transient pair-setup

M1 `{state 1, method 0}` → M2 `{state 2, salt, public}`; M3 `{state 3, public,
proof}` → M4 `{state 4, proof}`. Both sides derive the control and event keys
from the SRP session key and the connection continues encrypted on the same
socket. No credential record is written.

## PIN pair-setup and identity exchange

M1–M4 run as above with the supplied code. M5 `{state 5, encrypted data}` carries
the controller identifier, its raw Ed25519 public key and a signature, sealed
with the pair-setup key and the nonce `PS-Msg05`. M6 `{state 6, encrypted data}`
carries the accessory identifier, its raw Ed25519 public key and a signature,
sealed with the nonce `PS-Msg06`. Each signature covers the HKDF output for its
direction, the signer's identifier and the signer's public key. The controller
stores the accessory identity only after the signature verifies; pair-verify on
a later connection then derives the channel keys.

## Pair-verify

A long-term pairing verifies in four messages. M1 carries the sender's X25519
public key; M2 carries the receiver's X25519 public key plus an encrypted
`identifier`/`signature` pair sealed with the nonce `PV-Msg02`. M3 seals the
sender's `identifier`/`signature` with the nonce `PV-Msg03`, and M4 is the
receiver's confirmation. Each signature covers the other side's X25519 public
key, the signer's identifier and its own X25519 public key. Both sides derive the
control and event keys from the X25519 shared secret once M4 is exchanged.

## Error TLV mapping

A rejection carries TLV `state` (`6`) and TLV `error` (`7`). The error value maps
onto the failure contract as:

| Error TLV | Meaning         | Failure code     |
| --------- | --------------- | ---------------- |
| `0x01`    | unknown         | `connect_failed` |
| `0x02`    | authentication  | `auth_failed`    |
| `0x03`    | backoff         | `auth_failed`    |
| `0x04`    | maximum peers   | `connect_failed` |
| `0x05`    | maximum tries   | `auth_failed`    |
| `0x06`    | unavailable     | `connect_failed` |
| `0x07`    | busy            | `connect_failed` |

A rejected pairing is retried on a fresh connection, never on the socket that
received the rejection, and stops after the attempt cap with `auth_failed`.

## Encrypted control framing

After the keys are installed the same socket carries frames only:

```
+----------------+----------------------+------------------+
| 2-byte length  | ciphertext (length)  | 16-byte tag      |
+----------------+----------------------+------------------+
```

- The length prefix is a 2-byte little-endian ciphertext length and is also the
  additional authenticated data for ChaCha20-Poly1305.
- The nonce is four zero bytes followed by the 8-byte little-endian counter.
- Each direction owns its counter, starting at zero on every connection. A
  counter advances only after a complete frame is written or read, and a frame
  whose counter is not the expected next value is rejected.
- A declared length above 1024 bytes fails the session before any bytes are
  buffered; a tag mismatch or a connection that ends mid-frame closes the
  socket and surfaces `auth_failed` or `connect_failed` respectively.


## `/info` and SETUP

A newly paired control connection asks `GET /info` once and decodes the binary
plist. The sender folds the payload into the device capability model, reading
`features` (the capability mask), `sf` (status flags), `srcvers`, `protovers`
and `osvers`; the session keeps the whole payload for later. A body that is not
a decodable binary plist fails the session with `connect_failed` and contributes
nothing to the model.

`POST /setup` carries a binary plist with `deviceID`, `sessionUUID`,
`groupUUID`, `timingProtocol` (the requested protocol) and `timingPort` (the
sender's responder port, non-zero), plus `eventPort` when an event listener is
running. The response's `timingProtocol`, `timingPort` and `feedbackInterval`
are recorded, the last as the keepalive period. A response that confirms
only a protocol the sender does not implement fails with `timing_error`.
Every session generates a fresh `sessionUUID` and `groupUUID`; retired
identifiers are never reused.

## Event channel and feedback

When the sender wants events it opens a listener before SETUP and advertises
`eventPort`. The receiver connects back to that port; every inbound frame is
decrypted with the events write key and each payload is decoded as a binary
plist and appended to the session's events. If that connection ends, the session
records the channel as lost instead of reporting a healthy session.

While the session is active, `POST /feedback` is sent whenever the receiver's
`feedbackInterval` has elapsed on `Airplay.clock`. Teardown stops the timer and
no feedback follows it. The harness simulates a receiver that stops tolerating
silence: with `feedback_interval` set and its `clock` advanced past it, the next
control frame is dropped and the connection closed, which the sender surfaces as
`connect_failed` and marks the session inactive. The harness drives these tests
with the `events`, `event_target`, `event_write_key`, `feedback_interval` and
`clock` knobs.

## Parameters, teardown and 401

Parameters are sent as `SET_PARAMETER /command` with a binary plist body.
Volume maps linearly in decibels: `-30 + 30 * volume`, so 0.0 is -30 dB,
0.5 is -15 dB and 1.0 is 0 dB. Metadata travels as
`{"metadata" => {"title", "artist", "album"}}` and is sent again whenever the
active item's metadata changes.

`POST /teardown` ends the session: the event channel is closed, feedback stops,
no further frame is sent for that session, and the retired `sessionUUID` and
`groupUUID` are not reused. A `401` answer to any control request surfaces
`auth_required`, discards the connection, and pairs again on a fresh connection
without repeating the failed request on the old socket.

## Credentials

A long-term pairing is one binary plist per device at
`$XDG_CONFIG_HOME/airplay/devices/<device>.plist` (falling back to
`~/.config/airplay/devices`), overridden by `AIRPLAY_CREDENTIALS_DIR`. The
directory is `0700`, the file `0600`, and writes go through a temporary file and
rename. A directory inside the repository is refused (`insecure_credentials_path`),
as is an unsafe device identifier (`invalid_credential_id`).

The record holds the device key, the pairing `identifier`, the controller's
Ed25519 `client_public`/`client_private`, the accessory's `accessory_public` and
`accessory_signature`, and `permissions`. Transient pairing writes nothing, so
"no record" is the ordinary unpaired state. The threat model is another local
user, backups and an accidental `git add`; an OS keychain is a named follow-up.

## Route selection

The route is a pure function of the device record: no network is touched. It
reads the 64-bit feature mask (`video` (0), `photo` (1), `audio` (9),
`unified_media_control` (38), `buffered_audio` (40), `ptp` (41), `pairing` (46),
`airplay2` (48), `video_v2` (49)), the status flags (`pin` (0x8),
`password` (0x80), `legacy_pairing` (0x200)), the `pw` password flag and whether
credentials are stored.

The ordered rows are `legacy_pairing`, `native_paired` (plan starts at
pair-verify), `native_unpaired` (plan starts at pair-setup), `legacy_video` and
`raop`; a record matching none of them falls back to legacy AirPlay 1. Hints
follow the bits: `ptp` selects PTP timing, otherwise NTP; `buffered_audio`
selects buffered streaming, otherwise realtime; `video_v2` selects the v2 video
flavour, otherwise legacy.

An explicit override short-circuits the table and records `override` as the
decision source. An override the device cannot support - AirPlay 2 native
without the HK pairing bit - fails with `unsupported_feature` naming AirPlay 2
native. The route is fixed once a session starts: a pairing failure on the
AirPlay 2 route surfaces and no legacy request is issued.
