# Tasks

## 1. Crypto primitives, plist codec and golden vectors

- [ ] 1.1 Implement the TLV8 codec (one-byte type, one-byte length, value; order preserved; unknown types carried through unchanged) in the pairing library; verify with unit tests that a mixed sequence round-trips item for item and that an unknown type re-encodes to the same bytes.
- [ ] 1.2 Add fragmentation and reassembly to the TLV8 codec (values over 255 bytes split into consecutive same-type items, consecutive same-type items joined on decode); verify by encoding a 600-byte value and asserting the 255/255/90 split reassembles, and by asserting two same-type values separated by another type stay separate.
- [ ] 1.3 Implement SRP-6a over `OpenSSL::BN` and SHA-512 with the RFC 5054 3072-bit group, generator 5, identity `Pair-Setup`, including value padding before hashing; verify the client public value, session key, proof and server proof against the recorded golden vector.
- [ ] 1.4 Implement HKDF-SHA512 channel-key derivation with the four documented salt/info pairs (`Control-Salt`/`Control-Write-Encryption-Key`, `Control-Salt`/`Control-Read-Encryption-Key`, `Events-Salt`/`Events-Write-Encryption-Key`, `Events-Salt`/`Events-Read-Encryption-Key`); verify each derived key against its golden vector and assert all four differ.
- [ ] 1.5 Implement the ChaCha20-Poly1305 control-frame codec (2-byte little-endian ciphertext length, ciphertext, 16-byte tag, length prefix as AAD, nonce = 4 zero bytes plus 8-byte little-endian counter); verify against a golden frame and a two-frame sequence whose nonces use counters 0 and 1.
- [ ] 1.6 Implement the startup capability probe for ChaCha20-Poly1305, X25519, Ed25519, HKDF-SHA512 and SHA-512; verify that stubbing any one primitive makes the probe raise an error naming that primitive.
- [ ] 1.7 Implement the raw-32-byte to OpenSSL DER adapter for X25519 and Ed25519 keys, isolated in one module; verify with RFC 7748 and RFC 8032 vectors that raw keys round-trip and a known signature verifies.
- [ ] 1.8 Implement binary plist decoding (header, object table, offset table, trailer; null, boolean, integers of 1/2/4/8 bytes, 32- and 64-bit reals, date, data, ASCII string, UTF-16BE string, array, dictionary); verify with a fixture containing every type and a fixture containing non-ASCII strings.
- [ ] 1.9 Implement binary plist encoding with encoder-fixed object ordering; verify that encoding a many-key dictionary twice in separate processes is byte-identical and that an independent binary plist reader (fixture decoder or `plutil`-class reader in the integration shell) reads the values back.
- [ ] 1.10 Wire the `plist` gem in for the XML representation and convert between it and the binary codec's value model; verify an XML fixture containing array, dictionary, date and data decodes, re-encodes and decodes equal.
- [ ] 1.11 Implement plist date handling on the 2001-01-01T00:00:00Z epoch and the malformed-input errors (truncated trailer, over-declared object count, unsupported marker, oversized document); verify a date round-trips through both representations and each malformed case raises its specific error rather than returning partial values.
- [ ] 1.12 Commit the golden vector fixtures (TLV8, SRP, HKDF, frame bytes, plists) with their provenance recorded beside them (RFC section or the reference implementation they were captured from); verify `test:protocol` fails when a vector file is edited to a wrong value.

## 2. In-process pairing and control harness

- [ ] 2.1 Add the virtual receiver's pairing mode to `airplay-fake-device`: `POST /pair-setup` and `POST /pair-verify` with scripted accept/reject outcomes and scripted TLV responses; verify a transient exchange and a PIN exchange both complete against it in `test:protocol`.
- [ ] 2.2 Make the harness receiver demand encrypted traffic once pair-verify completes; verify a scenario in which a plaintext request after pairing is answered with a connection close and the sender reports the documented failure.
- [ ] 2.3 Add the fault-injection knobs: wrong PIN, 401 on the first control request, corrupted authentication tag, replayed counter, truncated frame, oversized declared length, and a post-rejection wedge that ignores all further bytes on the socket; verify each knob produces the observable its scenario requires.
- [ ] 2.4 Add the harness control surface the later groups need: scripted `/info` body, recorded request list, injectable clock and feedback interval, scripted event-channel messages on the reverse connection; verify by asserting the recorded request list for one trivial session.
- [ ] 2.5 Document every harness knob and its fault it simulates in the fake-device package notes; verify the list matches the knob constants exposed by the harness module.

## 3. Pairing flows

- [ ] 3.1 Implement transient pair-setup (four messages, fixed code 3939, `X-Apple-HKP: 4`) and hand the derived key to the encryption layer; verify against the harness and assert no credential record is written for the device.
- [ ] 3.2 Implement PIN/password pair-setup (six messages, Ed25519 identity exchange, receiver-signature verification, `X-Apple-HKP: 3`); verify a correct code stores a usable record and a wrong code yields `auth_failed` with nothing stored.
- [ ] 3.3 Implement flow selection from the `X-Apple-HKP` header and reject an unrecognised flow with `connect_failed`; verify with a table-driven test over values `4`, `3` and an unknown value asserting message counts and codes.
- [ ] 3.4 Implement the receiver pairing error TLV mapping (authentication, backoff, max tries, unavailable, busy, unknown) onto the failure contract; verify each value with a scripted harness response.
- [ ] 3.5 Implement the bounded retry on a fresh connection after a rejection; verify against the wedged-receiver knob that the abandoned socket receives no further bytes, that the retry succeeds on a new connection, and that an always-rejecting receiver stops at the attempt cap with `auth_failed`.
- [ ] 3.6 Write the pairing flow notes (message counts per flow, header selection, fixed transient code, error TLV mapping); verify the notes match the implemented constants read from the source.

## 4. Pair-verify and the encrypted channel

- [ ] 4.1 Implement pair-verify M1–M4 (X25519 ECDH plus Ed25519 signatures over both public keys) using stored long-term credentials, with `auth_failed` on any signature failure; verify the derived shared secret against its golden vector and a full exchange against the harness.
- [ ] 4.2 Implement the in-place plaintext-to-framed switch after pair-verify on the same connection; verify that the request immediately following the pair-verify exchange is framed and that the harness's plaintext-rejection knob is never triggered.
- [ ] 4.3 Implement fail-closed decryption (tag mismatch and unexpected counter close the connection, surface `auth_failed`, emit no decrypted bytes); verify with the corrupted-tag and replayed-counter knobs.
- [ ] 4.4 Implement frame length bounds and mid-frame EOF handling; verify the oversized-length knob fails fast with `connect_failed` without buffering and the truncated-frame knob fails the session instead of waiting.
- [ ] 4.5 Implement counter lifetime rules: counters reset on a new connection, advance only on a complete frame, and a partial write tears the connection down; verify the first frame of a second connection uses counter 0.
- [ ] 4.6 Write the framing notes (byte layout, AAD, nonce construction, counter direction and lifetime); verify the notes state the byte order and AAD exactly as the frame codec implements them.

## 5. Info and session setup

- [ ] 5.1 Implement `GET /info` with binary plist decoding and fail the session with `connect_failed` when the body is not a decodable binary plist; verify both paths against scripted harness bodies.
- [ ] 5.2 Feed the decoded `/info` payload into the device capability model so it becomes the authoritative source for the session; verify exactly one `/info` request per connection and that reconciled keys report the authoritative source.
- [ ] 5.3 Implement the `POST /setup` request (sender device identity, session UUID, group UUID, requested timing protocol, timing port) as a binary plist; verify the decoded request body from the harness contains all five.
- [ ] 5.4 Implement fresh session and group UUID generation per session; verify two consecutive sessions against the same device produce four distinct identifiers and that retired UUIDs are never reused.
- [ ] 5.5 Implement timing protocol negotiation from the SETUP response, recording the confirmed protocol and timing port, and failing with a timing error when the receiver confirms only an unimplemented protocol; verify both cases against scripted harness responses.
- [ ] 5.6 Write the `/info` and `SETUP` field notes (what the sender reads, what it sends, timing negotiation outcome); verify the notes match the fields the implementation actually accesses.

## 6. Event channel and feedback

- [ ] 6.1 Implement the event listener on the advertised event port: accept the receiver's reverse connection, decrypt its frames and surface each decoded event plist; verify with a scripted event from the harness.
- [ ] 6.2 Record and surface loss of the event channel instead of reporting a healthy session; verify the harness closes the event connection and the session observes it.
- [ ] 6.3 Implement the periodic `POST /feedback` keepalive driven by the injectable clock at the receiver-required interval, stopping when the session ends; verify one feedback per tick and no feedback after teardown.
- [ ] 6.4 Verify the missing-feedback case: the harness tears the session down when feedback is withheld beyond the interval and the sender surfaces the termination rather than reporting an active session.
- [ ] 6.5 Write the event channel and feedback notes (who connects where, encryption, interval source, termination consequences); verify the notes match the harness knobs used to test them.

## 7. Parameters, volume, metadata and teardown

- [ ] 7.1 Implement `SET_PARAMETER` on the encrypted channel and the volume curve mapping 0.0–1.0 linearly onto −30–0 dB; verify decoded request bodies carry −30, −15 and 0 dB for volumes 0.0, 0.5 and 1.0.
- [ ] 7.2 Implement track metadata parameters and re-send them whenever the metadata changes; verify the harness's most recent parameters contain title, artist and album after a set, and again after a change.
- [ ] 7.3 Implement `POST /teardown`: close the event channel, stop feedback, send nothing further for the session and retire its UUIDs; verify no frame or feedback is observed after teardown and the next session uses new UUIDs.
- [ ] 7.4 Implement handling of a `401` answer to any control request (surface `auth_required`, discard the connection, re-authenticate on a fresh one, never repeat the request on the same connection); verify with the harness's 401 knob that a new connection re-pairs and succeeds.
- [ ] 7.5 Write the parameters/volume/metadata notes (curve definition with the three anchor points, metadata re-send rule, teardown consequences, 401 handling); verify the notes match the assertions in the tests.

## 8. Credentials and the error contract

- [ ] 8.1 Implement the credential store: per-device record under the XDG config directory (with environment override), directory mode `0700`, file mode `0600`, atomic temporary-file-plus-rename write, and refusal of any path inside the repository; verify all four properties in a tmpdir test including the refusal case.
- [ ] 8.2 Implement the credential record contents (device identifier, client Ed25519 key pair, accessory public key and signature, pairing identifier, granted permissions) using the binary plist codec; verify a store/load round-trip reproduces the record exactly and a record for an unknown device reports "unpaired".
- [ ] 8.3 Verify the absent-credentials path: a device with no record starts at pair-setup with no `auth_failed`, and the record written on success is usable by the next session's pair-verify.
- [ ] 8.4 Wire the failure taxonomy so every failure on this path surfaces exactly one of `auth_required`, `auth_failed` or `connect_failed` with the device identity attached; verify with tests for a missing required password, a wrong password, a rejected pairing, a refused connection and a tag failure.
- [ ] 8.5 Implement the deferred-mechanism error: a receiver demanding FairPlay `fp-setup`, MFi `auth-setup` or HAP accessory mode fails with `unsupported_feature` naming the mechanism before any session state or credential exists; verify both the FairPlay and MFi cases against scripted harness responses.
- [ ] 8.6 Write the credential notes (path, format, permissions, threat model, what transient pairing does and does not persist); verify the notes match the storage test's observed paths and modes.

## 9. Route selection

- [ ] 9.1 Implement the route decision as a pure function over a device record (feature mask, status flags, password flag, credential presence) with the decision rows expressed as data; verify a decision is returned with no network access recorded by the harness.
- [ ] 9.2 Implement the AirPlay 2 native route rows (bits 38 or 48 with bit 46, credentials present) and the unpaired variant whose session plan begins at pair-setup; verify both with device-record fixtures and assert the session plan's first step.
- [ ] 9.3 Implement the password-flag row so a device advertising password protection requires a password and a session started without one fails with `auth_required` before any pairing material is sent; verify the harness records no pairing request.
- [ ] 9.4 Implement the legacy AirPlay 1 row (no AirPlay 2 bit, legacy video bit set) and the RAOP-compat row (`_raop` service, no AirPlay 2 bit, no legacy video); verify both with fixtures.
- [ ] 9.5 Implement the timing, stream-type and video-flavour hints attached to the decision (bits 41, 40 and 49); verify set/clear pairs yield PTP/buffered/video-v2 and NTP/realtime/legacy hints.
- [ ] 9.6 Implement the explicit override (short-circuits the table, recorded as the decision source) and `unsupported_feature` for an override the device cannot support; verify an override that wins over the table and an impossible override that is rejected.
- [ ] 9.7 Verify the fixed-route rule: a session routed to AirPlay 2 native that fails during pairing surfaces the failure and issues no legacy request, asserted against the harness's recorded request list.
- [ ] 9.8 Verify table precedence with explicit cases (AirPlay 2 capability beats legacy video; override beats the table; an extra unrelated feature bit does not change the route).
- [ ] 9.9 Write the route notes (the bit meanings read, the row order, the override rule, the fixed-route rule, what the hints mean and who consumes them); verify the notes enumerate the same bits the table reads.

## 10. Documentation

- [ ] 10.1 Write the protocol notes covering the whole path end to end (pairing flows, framing, control requests, route decision) as one document under the library's docs; verify every code and byte order in the notes matches a constant in the source.
- [ ] 10.2 Update the project README's capability statement: what works on AirPlay 2 receivers after this change, and what is deferred (FairPlay, MFi, HAP accessory mode, PTP timing); verify the deferred list matches the error names the code can raise.
- [ ] 10.3 Add structured logging for pairing attempts, route decisions and reconciliation outcomes with credential material redacted; verify a test that pairs, routes and reconciles leaves no key, password or proof bytes in the captured log output.

## Workflow follow-up

- Archive `mdns-discovery` before archiving this change, because this change's `device-capabilities` delta adds requirements to a capability that `mdns-discovery` creates; the same ordering rule applies to whichever store holds the specs.
- `airplay2-control-channel` and `route-selection` deltas here are complete for this change's scope; `airplay2-video-playqueue` and `raop-audio-stream` later add their own ADDED requirements under those paths, so they must be archived after this change.
- PTP timing is named and deliberately not scaffolded (see the `raop-audio-stream` follow-up `ptp-timing`); when it lands, the timing hint recorded here is the input it extends.
- OS keychain credential storage is a named follow-up of Decision 6 in `design.md`; the record format is deliberately self-contained so it can be moved without a wire change.
