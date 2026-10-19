# Proposal

## Why

Modern receivers — tvOS 15 and later, HomePod, and most third-party AirPlay 2 speakers — refuse
unauthenticated control. AirPlay 1 was one well-known RSA key and AES-CBC over plaintext RTSP;
AirPlay 2 replaces all of that with HomeKit-style pairing (SRP-6a, X25519, Ed25519), HKDF
derived per-channel keys, and a ChaCha20-Poly1305-encrypted control channel carrying binary
plists. Nothing this project can do on a current Apple TV (video, audio, volume, metadata,
transport) starts until that gate opens, and the gate has to open before routing can even be
decided, because the decision depends on stored credentials. This change builds the pairing
and encrypted control plane, and the route policy that uses it.

## What Changes

- Implement the TLV8 codec used by all pairing exchanges (including fragmentation for values
  over 255 bytes) and the pairing error codes the receiver can return.
- Implement `POST /pair-setup`: SRP-6a with the 3072-bit group and SHA-512, identity
  `"Pair-Setup"`, both transient (fixed code 3939, M1–M4) and PIN/password (M1–M6, Ed25519
  identity exchange) flows, selected via `X-Apple-HKP: 4` and `X-Apple-HKP: 3`.
- Implement `POST /pair-verify` (X25519 ECDH + Ed25519 signatures, M1–M4) and the HKDF-SHA512
  key derivation table for the control, event and data channels, including the exact
  salt/info strings and nonce construction.
- Frame and encrypt the control channel after pairing: `[u16 LE length][ciphertext][16-byte
  tag]`, ChaCha20-Poly1305, independent 8-byte little-endian counters per direction, length as
  AAD, fail-closed on tag mismatch.
- Implement the authenticated control plane: `GET /info` reconciled against the TXT capability
  model, session `SETUP` (device identity, session/group UUIDs, timing negotiation), the
  reverse event channel, periodic `POST /feedback`, `SET_PARAMETER` for volume (the
  ecosystem's linear-in-dB −30..0 dB curve) and metadata, and `TEARDOWN`.
- Add a binary/XML plist codec (including plist date values) — required by `/info`, `SETUP` and
  the modern command flow — and make the XML and binary representations equally testable.
- Persist credentials outside the repo (per-device identity, pairing keys, permissions, home
  identifier) with restrictive permissions, and make "no credentials yet" a normal state.
- Define route selection as specified behavior rather than an implementation detail: feature
  bits 38/48 (AirPlay 2 / pairing-capable), 46 (HK pairing and access control), 41 (PTP),
  40 (buffered audio), 49 (video v2), plus `flags`/`sf` (PIN required, legacy pairing) and
  `pw` (password required), resolving to legacy AirPlay 1, RAOP-compat or AirPlay 2 native;
  including the self-selecting password path where a rejected pairing retries on a fresh
  connection instead of deadlocking the receiver's state machine.
- Establish the machine-readable error contract for every non-200 on this path
  (`auth_required`, `auth_failed`, `connect_failed`) so callers can distinguish "needs a
  password" from "the password was wrong" from "the device refused".
- Explicitly not in this change: FairPlay `fp-setup` and MFi `auth-setup` (deferred, with a
  clear error when a receiver demands them), HAP accessory mode, and any playback.

## Capabilities

### New Capabilities
- `airplay2-pairing`: TLV8, SRP-6a pair-setup (transient and PIN), pair-verify, HKDF channel
  keys, encrypted control framing, credential persistence and the pairing error contract.
- `airplay2-control-channel`: the authenticated session control plane — `/info`, session SETUP,
  event channel, feedback keepalive, volume/metadata parameters and teardown.
- `route-selection`: the capability- and credential-driven decision between legacy AirPlay 1,
  RAOP-compat and AirPlay 2 native, including timing and stream-type selection hints.
- `plist-codec`: binary and XML property-list encoding/decoding used by every modern exchange.

### Modified Capabilities
- `device-capabilities`, introduced by the sibling change `mdns-discovery`, grows here: this change
  contributes the requirement that TXT-derived capabilities are reconciled with the authoritative
  `GET /info` response, with the wire response winning on conflict. The delta is `ADDED`, not
  `MODIFIED`, because no base spec exists under `openspec/specs/` until that change is archived, and
  `MODIFIED` with partial content loses detail at archive time.
- `test-harness`, introduced by the sibling change `runtime-async-reset`, grows here: this change
  contributes the virtual receiver mode that performs the HAP pairing handshake and then requires
  encrypted control traffic, the recording of decrypted encrypted-exchange traffic, the pairing
  fault configuration (rejected pairing, `401` challenge, corrupted authentication tag, replayed
  counter, wedged receiver) and the injectable clock the feedback interval is asserted with. The
  delta is `ADDED`, not `MODIFIED`, for the same reason: no base spec exists under
  `openspec/specs/` until that change is archived.

## Impact

- Adds a new library subtree for pairing/auth, channel framing and plists; the `Async` stream
  layer replaces `net-ptth` for both encrypted and plaintext control connections.
- `airplay2-video-playqueue` and `raop-audio-stream` both depend on this change for their
  connection, encryption, timing negotiation and event channel; neither can be implemented
  before it.
- Harness slice: golden vectors for TLV8 fragmentation, SRP (3072/SHA-512), the HKDF salt/info
  table, frame layout, nonce counters and plist encoding; a virtual receiver that performs the
  pairing handshake and then insists on encrypted traffic; and fault injection for wrong PIN,
  `401` challenge, authentication tag failure, replayed counters and receivers that wedge their
  pairing state machine after a rejection.
