# airplay2-pairing Specification

## Purpose

Opens the authentication gate every modern AirPlay 2 receiver imposes: TLV8 exchanges, SRP-6a and PIN/transient pair-setup, pair-verify key agreement, the encrypted control framing, credential persistence and the machine-readable pairing failure contract that the rest of the sender depends on.

## Requirements

### Requirement: TLV8 encode and decode

The sender SHALL encode and decode type-length-value items consisting of a one-byte type, a one-byte length and that many value bytes, preserving item order and carrying unrecognised types through unchanged.

```ruby
hello = Airplay::Pairing::TLV8::Item.new(0x03, public_key)
bytes = Airplay::Pairing::TLV8.encode([hello])
Airplay::Pairing::TLV8.decode(bytes) # => [#<Item type=3 value="...">]
```

#### Scenario: Small items round-trip in order

- **WHEN** a sequence of type-length-value items with values shorter than 256 bytes is encoded and the result is decoded
- **THEN** the decoded sequence equals the input sequence, item for item and byte for byte, in the original order

#### Scenario: Unknown types survive a round-trip

- **WHEN** an item whose type the sender has no semantic for is decoded and re-encoded
- **THEN** the item is emitted with the same type and the same value bytes

### Requirement: TLV8 fragmentation and reassembly

A value longer than 255 bytes SHALL be emitted as consecutive items of the same type, each carrying at most 255 bytes, and decoding SHALL reassemble consecutive same-type fragments by concatenation before yielding a value.

```ruby
bytes = Airplay::Pairing::TLV8.encode([Airplay::Pairing::TLV8::Item.new(0x03, "x" * 600)])
Airplay::Pairing::TLV8.decode(bytes).first.value.bytesize # => 600
```

#### Scenario: A 600-byte value is fragmented

- **WHEN** a 600-byte value is encoded
- **THEN** three consecutive items of that type carry 255, 255 and 90 bytes, and decoding the result yields the original 600 bytes

#### Scenario: Fragments of one value are not merged across a boundary

- **WHEN** two independently encoded values of the same type are separated in the stream by an item of a different type
- **THEN** decoding yields two separate values, not one concatenated value

### Requirement: SRP-6a parameters

Pair-setup SHALL use SRP-6a with the RFC 5054 3072-bit group, generator 5, SHA-512 and the pairing identity `Pair-Setup`, and the sender MUST reject any group, generator or hash other than those.

```ruby
srp = Airplay::Pairing::SRP.new(pin: 3939)
srp.process(receiver_public, receiver_salt)
srp.public                                  # own A, sent in M3
srp.proof                                   # M1
srp.valid_server_proof?(receiver_proof)     # M2 check
```

#### Scenario: Golden vector reproduces the published proof

- **WHEN** the fixed reference verifier, salt and client private value are supplied to the pair-setup computation
- **THEN** the computed public value, scrambled value and both proof messages equal the golden vector held by the test suite

### Requirement: Transient pair-setup

When pairing is requested as transient, the sender SHALL complete the four-message pair-setup exchange using the fixed code `3939` and SHALL NOT create, transmit or store a long-term identity.

```ruby
setup = Airplay::Pairing::Setup.pair(device) # header 4, fixed code 3939
setup.control_keys # => [write_key, read_key]
setup.record       # => nil: nothing persisted
```

#### Scenario: Transient pairing opens a session without persisting anything

- **WHEN** the sender pairs transiently with a virtual receiver that accepts code `3939`
- **THEN** the exchange completes after four messages, the derived key is handed to the encryption layer, and no credential record is written for the device

#### Scenario: Transient pairing is offered before credentials exist

- **WHEN** the sender connects to a device it has never paired with and selects transient pairing
- **THEN** the receiver accepts the exchange without any prior stored state on either side

### Requirement: PIN pair-setup with identity exchange

When pairing is requested as PIN/password, the sender SHALL complete the six-message exchange with the supplied code, exchange Ed25519 identity keys, and verify the receiver's signature over the exchanged material before storing any credential.

```ruby
setup = Airplay::Pairing::Setup.pair(device, code: "1234", transient: false)
setup.record["client_public"].bytes.bytesize # => 32
```

#### Scenario: A correct code produces a stored long-term pairing

- **WHEN** the sender supplies the correct code and the receiver returns its identity and signature
- **THEN** the signature verifies, a credential record for the device is stored, and the record is usable by pair-verify

#### Scenario: A wrong code is reported as an authentication failure

- **WHEN** the sender supplies an incorrect code
- **THEN** the receiver's authentication error is surfaced as `auth_failed` and no credential record is written

### Requirement: Pairing flow selection

The sender SHALL select the pair-setup flow from the `X-Apple-HKP` header value on the pairing request, using `4` for transient pairing and `3` for PIN/password pairing.

```ruby
Airplay::Pairing::Setup.from_header("4")                 # => transient
Airplay::Pairing::Setup.from_header("3", code: "1234")  # => PIN
```

#### Scenario: Header value selects the flow

- **WHEN** the sender pairs with header value `4` and again with header value `3`
- **THEN** the first exchange ends after the fourth message and the second continues through the sixth, with the header value that selected each flow recorded in the session log

#### Scenario: An unrecognised header value is not guessed

- **WHEN** a pairing response indicates a flow the sender does not implement
- **THEN** the session fails with `connect_failed` instead of attempting one of the two known flows

### Requirement: Pair-verify

After a stored long-term pairing, the sender SHALL perform pair-verify over four messages using X25519 ECDH with the stored keys and Ed25519 signatures covering both parties' public keys, and MUST abort with `auth_failed` when any signature fails verification.

```ruby
verify = Airplay::Pairing::Verify.new(record)
verify.run(connection)      # installs the frame keys on the same connection
verify.shared_secret        # X25519 shared secret
```

#### Scenario: Signatures verify and a shared secret is agreed

- **WHEN** both parties exchange public keys and mutually verify the signatures over them
- **THEN** the sender derives the same shared secret the golden vector predicts and proceeds to key derivation

#### Scenario: A forged signature aborts the session

- **WHEN** the peer's signature does not verify over the exchanged public keys
- **THEN** the session ends with `auth_failed` and no key material is derived

### Requirement: Per-channel key derivation

The sender SHALL derive channel keys with HKDF-SHA512 using the documented salt and info string pairs (`Control-Salt` with `Control-Write-Encryption-Key` and `Control-Read-Encryption-Key`, `Events-Salt` with `Events-Write-Encryption-Key` and `Events-Read-Encryption-Key`), yielding a distinct key per channel and direction.

```ruby
write, read = Airplay::Pairing::HKDF.control_keys(shared_secret)
event_write, event_read = Airplay::Pairing::HKDF.event_keys(shared_secret)
```

#### Scenario: Golden vectors match for every salt and info pair

- **WHEN** a fixed shared secret is expanded for each of the four documented salt/info pairs
- **THEN** each derived key equals its golden vector and the four keys are pairwise different

#### Scenario: Read and write keys are not interchangeable

- **WHEN** a frame is encrypted with the read key of a channel
- **THEN** decrypting it with the write key of that channel fails the authentication check

### Requirement: Encrypted control framing

After pairing succeeds, every byte on the control connection SHALL be framed as a 16-bit little-endian ciphertext length followed by that many ciphertext bytes and a 16-byte authentication tag, produced with ChaCha20-Poly1305 using the two length bytes as additional authenticated data.

```ruby
writer = Airplay::Pairing::Frame.new(write_key)
reader = Airplay::Pairing::Frame.new(read_key)
reader.decrypt(writer.encrypt(plist_bytes)) # => plist_bytes
```

#### Scenario: Frames match the golden byte layout

- **WHEN** a known plaintext is encoded with a known key and counter
- **THEN** the emitted bytes are the 2-byte little-endian length, the ciphertext of that length and the 16-byte tag, identical to the golden frame

#### Scenario: Consecutive frames decrypt independently

- **WHEN** two requests are sent back to back on an encrypted connection
- **THEN** the receiver decrypts each frame with its own header and both requests are handled

### Requirement: Per-direction frame counters

Each direction SHALL maintain its own 64-bit frame counter starting at zero and incrementing by one per frame, the nonce SHALL be four zero bytes followed by that counter in little-endian order, and a frame whose counter is not the expected next value MUST be rejected.

```ruby
frame = Airplay::Pairing::Frame.new(key)
frame.encrypt("a")
frame.encrypt("b")
frame.counter # => 2
```

#### Scenario: Nonces advance with the counter

- **WHEN** three frames are sent in one direction
- **THEN** their nonces use counters 0, 1 and 2 and are otherwise identical

#### Scenario: A replayed frame is rejected

- **WHEN** a frame that has already been accepted is delivered a second time
- **THEN** the receiver rejects it and terminates the connection instead of handling it again

### Requirement: Fail-closed on authentication failure

A frame whose authentication tag does not verify MUST close the connection immediately, MUST NOT surface any decrypted bytes and MUST surface `auth_failed` to the caller.

```ruby
begin
  reader.decrypt(tampered_frame)
rescue Airplay::AuthFailedError => error
  error.code # => :auth_failed
end
```

#### Scenario: A corrupted tag closes the connection

- **WHEN** a received frame has one bit flipped in its ciphertext or tag
- **THEN** the connection is closed without any request being handled and the caller observes `auth_failed`

### Requirement: Frame length validation

A declared ciphertext length larger than the maximum accepted frame size, or a connection that ends part-way through a frame, MUST fail the session with the connection error code rather than be buffered without bound.

```ruby
Airplay::Pairing::Frame::MAX_LENGTH # => 1024
reader.decrypt([2000].pack("v") + ("x" * 2000)) # raises :oversized_frame
```

#### Scenario: An oversized declared length fails fast

- **WHEN** a frame header declares a length above the accepted maximum
- **THEN** the session fails with `connect_failed` and the bytes are not buffered

#### Scenario: Truncation mid-frame fails the session

- **WHEN** the peer closes the connection after sending fewer bytes than the frame's declared length requires
- **THEN** the session fails with `connect_failed` instead of waiting

### Requirement: Credential persistence

Long-term pairings SHALL be stored outside the repository, one record per device, with directory mode `0700` and file mode `0600`, written atomically via a temporary file and rename, and no repository path SHALL be accepted as a credential location.

```ruby
store = Airplay::Pairing::CredentialStore.new
store.write(record)
store.path_for("device-1") # => "$XDG_CONFIG_HOME/airplay/devices/device-1.plist"
```

#### Scenario: A stored record is private and outside the repository

- **WHEN** a long-term pairing completes
- **THEN** the record exists under the configured credential directory outside the repository tree with file mode `0600` in a directory of mode `0700`

#### Scenario: A repository path is refused

- **WHEN** the credential directory is configured to a path inside the repository
- **THEN** the sender refuses the configuration with a specific error and does not write the record

### Requirement: Absent credentials are a normal state

A device with no stored credentials SHALL be treated as unpaired rather than as a failure: the session offers pair-setup, and the caller sees a route that includes pairing.

```ruby
store.unpaired?("device-1") # => true
store.read("device-1")      # => nil
```

#### Scenario: A first-time device is not an error

- **WHEN** the sender connects to a device with no credential record
- **THEN** no `auth_failed` is raised, the connection begins with pair-setup, and the resulting credentials are stored on success

### Requirement: Pairing failure codes

Every failure on the pairing and encrypted control path SHALL surface exactly one machine-readable code: `auth_required` when the receiver needs a password or code the sender does not have, `auth_failed` when the receiver rejected supplied credentials or pairing material, and `connect_failed` when the connection could not be established or was refused.

```ruby
# each failure attaches the device identity
error.code # => :auth_required, :auth_failed or :connect_failed
error.device # => "Living Room"
```

#### Scenario: The three codes are distinguishable

- **WHEN** a session fails because no password was configured for a password-protected device, then because a wrong password was supplied, then because the peer refused the connection
- **THEN** the caller observes `auth_required`, `auth_failed` and `connect_failed` respectively, each with the device identity attached

### Requirement: Retry on a fresh connection

After a receiver rejects a pairing attempt, the sender MUST discard that connection and perform any further attempt on a new connection within a bounded attempt count, and MUST NOT send further pairing messages on a connection that has already failed.

```ruby
Airplay::Pairing::Setup.pair(device, attempts: 2)
# each attempt opens a new connection; the rejected socket is never reused
```

#### Scenario: A wedged receiver recovers on a new connection

- **WHEN** a virtual receiver answers the first pair-setup with an authentication error and thereafter ignores every message on that socket
- **THEN** the sender closes that socket, opens a new connection for the retry and succeeds without sending anything else on the wedged socket

#### Scenario: Retries are bounded

- **WHEN** every pairing attempt is rejected
- **THEN** the sender stops after the configured attempt count and reports `auth_failed` instead of retrying indefinitely

### Requirement: Deferred authentication mechanisms

FairPlay `fp-setup`, MFi `auth-setup` and HAP accessory mode SHALL NOT be implemented, and a receiver that demands one MUST fail with an `unsupported_feature` error naming the mechanism before any session state is created.

```ruby
Airplay::Pairing::Unsupported::MECHANISMS
# => {"fp-setup"=>"FairPlay", "auth-setup"=>"MFi", "accessory"=>"HAP accessory mode"}
```

#### Scenario: A FairPlay demand fails with an actionable error

- **WHEN** a receiver answers the discovery or pairing exchange by demanding FairPlay before it accepts control
- **THEN** the session fails with `unsupported_feature` naming FairPlay and no partial session or credential is left behind

#### Scenario: An MFi demand is named as such

- **WHEN** a receiver demands MFi authentication
- **THEN** the error names MFi, distinguishing it from the FairPlay case

### Requirement: Reviewable pairing examples

The change SHALL keep a reviewable Ruby sample for each implemented pairing primitive, so a
reviewer can see the intended usage without reading the implementation.

Transient pairing is the implemented first slice: TLV8, SRP-6a with code `3939`,
HKDF, AEAD framing and binary plists. PIN/pair-verify credential persistence is deferred.

```ruby
# TLV8
hello = Airplay::Pairing::TLV8::Item.new(0x03, public_key)
bytes = Airplay::Pairing::TLV8.encode([hello])
Airplay::Pairing::TLV8.decode(bytes) # => [#<Item type=3 value="...">]

# SRP-6a: A -> receiver, then B + salt -> key and proof
srp = Airplay::Pairing::SRP.new(pin: 3939)
srp.process(receiver_public, receiver_salt)
srp.public                # own A, sent in M3
srp.key                   # 64-byte SRP session key
srp.proof                 # M1, sent in M3
srp.valid_server_proof?(receiver_proof) # M2 check

# Channel keys and framing
write_key, read_key = Airplay::Pairing::HKDF.control_keys(srp.key)
writer = Airplay::Pairing::Frame.new(write_key)
reader = Airplay::Pairing::Frame.new(read_key)
frame = writer.encrypt(plist_bytes) # 0x00 0x14 + ciphertext + tag
reader.decrypt(frame)               # raises Airplay::AuthFailedError on a bad tag
```

#### Scenario: Example transient exchange

- **WHEN** the sender posts M1 with method `PairSetup`, state `1` and flags `0x10`
- **THEN** the receiver answers with salt and public key, the sender posts M3 with its public key and proof, and the receiver's M4 proof is verified before deriving the control keys from `srp.key`

