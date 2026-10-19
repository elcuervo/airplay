# Design

## Context

See `proposal.md` for motivation. The constraints that shape this design:

- The receiver, not the sender, chooses which pairing flow runs. `X-Apple-HKP` on the request
  selects transient (`4`) or PIN/password (`3`), and the exchanges are short, strictly
  ordered TLV8 message pairs on one connection. Nothing about that is negotiable.
- Everything after pairing is a single byte stream that changes meaning once pair-verify
  completes: plaintext RTSP-shaped requests before, length-prefixed AEAD frames after. There is
  no second connection and no handshake message announcing the switch.
- `runtime-async-reset` already fixes the runtime (`async ~> 2.46`), the error taxonomy with
  machine-readable codes, and the `plist` gem; this change adds no new native dependency and no
  new concurrency model.
- The in-process virtual receiver from `test-harness` is the only oracle: no physical AirPlay
  hardware is available, and pairing cannot be validated against a device we do not own. The
  pairing/control modes and faults this change needs are an ADDED delta on that capability in
  `specs/test-harness/spec.md` (`runtime-async-reset` owns it and its base spec does not exist
  until that change is archived).
- This change is the floor for `airplay2-video-playqueue` (extends `airplay2-control-channel`)
  and `raop-audio-stream` (extends `airplay2-control-channel` and `route-selection`), so the
  session and framing seams must be usable by them without reopening the pairing design.

## Goals / Non-Goals

**Goals:**

- Make the pairing/encryption path assertable at the byte level: every wire artifact (TLV8
  fragments, SRP proofs, derived keys, frame bytes, plist documents) has a golden vector.
- Make the route decision a data table that a fixture can exercise exhaustively without a
  network, so route bugs are testable per row rather than by observation.
- Give the two downstream changes a session seam (encrypted stream + negotiated timing +
  event channel) they can extend by adding streams, without touching pairing or framing.

**Non-Goals:**

- No playback, transport, queue or streaming behavior — only the control plane those need.
- No PTP engine, no FairPlay, no MFi, no HAP accessory mode (see Decisions 8).
- No OS keychain integration, no credential sync between hosts.
- No attempt to make XML plists byte-deterministic; only the binary representation carries that
  guarantee, because only the binary representation is asserted byte-for-byte.

## Decisions

### 1. SRP-6a implemented in-repo over `OpenSSL::BN` + `OpenSSL::Digest`, not a gem

**Decision:** Implement SRP-6a inline: `OpenSSL::BN` for the 3072-bit modexp and group
arithmetic, `OpenSSL::Digest::SHA512` for `H`, with the RFC 5054 3072-bit group and generator
5, identity `Pair-Setup`. Pad both public values to the group length before hashing (`PAD`) as
the variant requires.

**Rationale:** No maintained Ruby gem implements the HAP variant (3072-bit group over SHA-512
with this proof shape). The arithmetic that must be trusted is ~40 lines; the group constants
and public values are a Matter of golden vectors, and a wrong implementation fails loudly at
the proof step against a reference vector rather than silently. `OpenSSL::BN` does the only
expensive operation (`mod_exp`) in C.

**Alternatives considered:** a third-party SRP gem — the available ones are small, unmaintained
and target SHA-1/2048-bit groups, none exposes the proof shape HAP expects, so we would end up
forking it; a pure-Ruby bignum implementation — correct but 10–100× slower for 3072-bit modexp
and pointless when `OpenSSL::BN` is already loaded; a C extension — new native dependency in a
project whose whole point in this change set is removing broken native deps.

### 2. OpenSSL primitives for all other cryptography, no pure-Ruby crypto

**Decision:** ChaCha20-Poly1305 (`OpenSSL::Cipher`), X25519 and Ed25519
(`OpenSSL::PKey.generate_key`), HKDF-SHA512 (`OpenSSL::KDF.hkdf`) and SHA-512 from the default
`openssl` gem. A startup capability probe checks that each primitive exists and raises a
specific error naming the missing one.

**Rationale:** OpenSSL 3.5.8 is reachable through the default gem on this host and provides all
five primitives, so no new dependency, no vendored cipher code, and constant-time behavior we
would not get from hand-written pure Ruby. The probe exists because the host's global gem set
is known-broken; the flake pins the interpreter and OpenSSL, and the probe makes a bad
environment fail with a legible message instead of an obscure key error.

**Alternatives considered:** `rbnacl`/libsodium — covers X25519/Ed25519 and
ChaCha20-Poly1305 but adds a bundled native extension, and HKDF-SHA512 would still come from
somewhere; pure-Ruby (`RubyNaCl`-style) — unacceptable side channels and speed for AEAD on the
control channel; `OpenSSL::PKey::EC` only — the API surface for X25519 there is the same
underlying EVP codepath, so no gain.

### 3. Raw 32-byte keys are adapters over OpenSSL's DER-shaped API, isolated behind one module

**Decision:** All key material in the wire protocol is raw 32 bytes; OpenSSL's Ruby binding
wants DER/`SubjectPublicKeyInfo` for X25519 and Ed25519. Wrap/unwrap with fixed prefix
constants in one adapter module, and never let DER leak past it.

**Rationale:** Pairing messages carry raw keys; if the wrapping prefix is wrong the failure
shows up as a signature mismatch a long way from the cause. Keeping the conversion in one place
makes it a testable unit and keeps the rest of the pairing code dealing in the bytes that are
actually on the wire.

**Alternatives considered:** keeping keys as OpenSSL objects everywhere — pushes DER handling
into every serialize/parse site and makes the golden vectors unreadable; using a gem that takes
raw keys — rejected with Decision 2.

### 4. `plist` gem for XML, in-repo codec for binary

**Decision:** Use the `plist` gem (adopted by `runtime-async-reset`) for the XML representation.
Implement the `bplist00` encoder and decoder in-repo over one shared value model, with the
encoder's object ordering fixed by the encoder itself.

**Rationale:** Byte-level assertions are a stated requirement and only exist for the binary
form; owning that encoder means we control object ordering, offset table and trailer rather
than inheriting whatever a gem's writer happens to emit. The XML form is a debugging and fixture
convenience, and `plist` already parses it.

**Alternatives considered:** CFPropertyList — handles binary natively but pulls a native
libxml2 extension and gives no ordering/determinism guarantee, which is exactly the property
the test suite needs; one codec for both forms written from scratch — more code to maintain
for the representation that appears least on the wire; XML everywhere — impossible, receivers
on this path require binary.

### 5. Framing composes as a transform beneath the request layer, switched in place

**Decision:** The encrypted framing is a frame reader/writer object wrapping the same
`Async::IO`-style connection: `read_frame`/`write_frame` handle the 2-byte length prefix, the
ciphertext and the tag, and own the per-direction counters. Requests are serialized over that
interface; nothing above it knows whether it is writing plaintext or ciphertext. After the
pair-verify exchange completes, the session flips the same connection from plaintext to framed
and the very next request is framed.

**Rationale:** There is no protocol signal for the switch, so the session must own it, and the
only safe place to own it is the layer that already sees every byte. A transform also means
partial reads are buffered exactly once, at the layer that knows the frame length, instead of
each request handler reimplementing a read loop.

**Alternatives considered:** an `async-http` middleware — RTSP-shaped requests are not
HTTP/2 framing and the connection is not an `Async::HTTP` connection once encrypted; a
separate "encrypted connection" object replacing the plaintext one — forces the pairing code to
hand over a socket mid-exchange, which is where receivers wedge; an FFI-like cipher stream
adapter — more machinery than 12 bytes of nonce and a length prefix justify.

### 6. Credentials: per-device file under an XDG config directory, 0700/0600, atomic write

**Decision:** Store one record per device as a binary plist at
`$XDG_CONFIG_HOME/airplay/devices/<device-id>.plist` (falling back to `~/.config/...`),
directory mode `0700`, file mode `0600`, written to a temporary file and renamed. An
environment override points the directory at a temporary path for tests and the harness. The
record holds the device identifier, the client's Ed25519 key pair, the accessory's public key
and signature, the pairing identifier and the granted permissions. A path inside the repository
is refused outright.

**Rationale:** The threat model is local: other users on the machine, backups, and accidental
`git add`. `0700`/`0600` outside the tree plus atomic write covers those and needs no session
bus. Transient pairings deliberately write nothing, so the "no credentials yet" state is
ordinary and distinguishable from "pairing failed".

**Alternatives considered:** an OS keychain via a helper — correct long-term answer, but a new
platform-specific dependency and an unlock prompt in a headless CLI, so it is deferred;
a single shared credential file — one corrupted or leaked file loses or exposes every device;
storing in the repository or beside the app — commit and reinstall hazards; encrypting the file
with a passphrase — moves the problem to passphrase storage with no user-facing benefit here.

### 7. Route selection as a table of predicate rows, not branching code

**Decision:** Express routing as ordered data rows (predicate over feature bits, flags,
password flag and credential presence → route), evaluated top-down, with the explicit override
short-circuiting the table and the resulting timing/stream-type/video hints attached to the
decision. Rows are the test fixture.

**Rationale:** Devices differ by which bits their firmware advertises, and the ordering between
rows (for example, AirPlay 2 capability before legacy video) is the actual policy. A table
makes both the rows and their order explicit and lets tests assert one row at a time — including
the rows a real device would never exercise. Branching code hides ordering in control flow, and
a scoring model cannot explain why a given device routed the way it did, which matters when a
user reports "my speaker was driven over the wrong protocol".

**Alternatives considered:** nested `if` chain — testable only through the whole function and
easy to reorder without noticing; numeric scores per capability — no row to point at when
explaining a route; deferring the decision to each transport — duplicates the policy and
guarantees drift.

### 8. FairPlay, MFi and HAP accessory mode are deferred behind one specific error

**Decision:** When a receiver demands FairPlay `fp-setup`, MFi `auth-setup` or HAP accessory
mode, the session fails with `unsupported_feature` naming the mechanism before any session
state exists, and logs the device identity and the demanded mechanism. The route table treats
"no HK pairing bit" as "no AirPlay 2 route", so devices that can only be reached after a
handshake we cannot perform are never routed there in the first place.

**Rationale:** These mechanisms need cryptographic constants and key material that are not
publicly specified and cannot be derived; pretending to implement them, or discovering the
demand deep inside a stream setup, produces a session that half-exists and a user who cannot
tell what went wrong. One named code at the boundary turns that into an actionable message ("this
device requires FairPlay, which this build does not implement; the legacy path is the
alternative when the device supports it").

**Alternatives considered:** attempting the handshake and failing wherever it fails — every
failure point gives a different, less informative error; falling back to the legacy route
silently — wrong for a device whose only working path requires the handshake, and it defeats
Decision 7's fixed-route rule; shipping a stub that answers `fp-setup` — see the `completeness`
rule: no no-op stand-ins in the shipped path.

## Risks / Trade-offs

- **[A wrong byte in pairing produces a receiver-side silent failure, not an error]** →
  Golden vectors for TLV8 fragmentation, SRP proofs, each HKDF salt/info pair, frame layout and
  counters; the virtual receiver refuses to proceed past any message whose bytes it does not
  expect, so a mistake fails the harness immediately instead of at a real device.
- **[The SRP variant on the wire may differ from RFC 5054 in padding or identity handling]** →
  Pin the parameters in a spec requirement; cross-check the implementation against vectors from
  a reference implementation (`pyatv`, shairport-sync's `pair_ap`) captured into the vector
  fixtures, and treat any mismatch as an implementation bug rather than adjusting the vector.
- **[A rejected pairing can wedge a receiver's state machine; a retry on the same socket hangs
  until timeout]** → The retry rule is a requirement: discard the socket and retry on a fresh
  connection, bounded attempt count, and the wedged-receiver case is a harness fault injection
  rather than a live discovery.
- **[Frame counters desynchronise if a frame is counted before its write actually lands]** →
  Increment only after a complete frame is written or read; a send failure tears the connection
  down rather than reusing it, since the peer's counter is now unrecoverable.
- **[OpenSSL version or primitive availability drift breaks the crypto silently at runtime]** →
  Startup probe for all five primitives with a specific error, plus the flake-pinned
  interpreter/OpenSSL; the probe failure message names the primitive so an environment problem
  is distinguishable from a protocol problem.
- **[Raw-to-DER key wrapping mistakes surface as signature failures far from their cause]** →
  The adapter module in Decision 3 is a unit with RFC 7748 / RFC 8032 vectors, and pairing logs
  which verification step failed rather than only the code.
- **[Credentials on disk are readable by any process running as the user]** → Accepted for this
  threat model and documented; file modes and location limit exposure to other users and VCS,
  and the record holds only pairing keys, not media. Keychain integration is a named follow-up.
- **[Route policy as a table can be edited into an inconsistent order]** → Table-order tests
  assert specific precedence cases (AirPlay 2 capability before legacy video, override before
  table), so a reorder that changes behavior fails a scenario rather than reaching a device.

## Open Questions

- Whether credential records should be exportable/importable so a user can carry a pairing to
  another host. Deferrable: nothing in the specs, the approach or the task breakdown changes if
  the answer is "no", and the storage format is already a self-contained document.
