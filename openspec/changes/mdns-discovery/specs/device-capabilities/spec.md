# Spec Delta

## Purpose

Turn a receiver's raw TXT record into a typed capability model — feature mask, status flags, version
gates, identity, group and access-control fields — so routing, pairing and playback decide on named
capabilities instead of re-parsing strings.

## ADDED Requirements

### Requirement: 64-bit feature mask decoding

The model SHALL decode the TXT `features` value into one 64-bit mask, reading `0xLOW,0xHIGH` as
`(HIGH << 32) | LOW`, accepting a single-word value, and falling back to `ft` when `features` is
absent. A missing or malformed value SHALL be reported as unknown, with every bit-derived predicate
false, and SHALL NOT raise.

#### Scenario: Two-word mask

- **WHEN** a receiver advertises `features=0x40000a00,0x80300`
- **THEN** the model reports the mask `0x0008030040000a00`

#### Scenario: Fallback to `ft`

- **WHEN** a receiver advertises a mask in `ft` and no `features` key
- **THEN** the model reports the mask from `ft`

#### Scenario: Malformed mask

- **WHEN** a receiver advertises `features=zz`
- **THEN** the mask is unknown, every bit-derived predicate is false and the record remains usable

### Requirement: Status flags and password predicates

The model SHALL parse the status-flag word from `sf`, falling back to `flags`, and SHALL expose the
documented conditions as predicates: a password is required when `pw` is true or the password bit is
set, a PIN is required when the PIN bit is set, and legacy pairing is advertised when the
legacy-pairing bit is set.

#### Scenario: Password advertised as a flag

- **WHEN** a receiver advertises `pw=true` with no flag bit set
- **THEN** the password-required predicate is true

#### Scenario: Password advertised as a bit

- **WHEN** a receiver advertises `sf=0x80`
- **THEN** the password-required predicate is true and the PIN-required predicate is false

#### Scenario: PIN and legacy-pairing bits

- **WHEN** a receiver advertises status flags with the PIN bit and the legacy-pairing bit set
- **THEN** both predicates are true

### Requirement: Version fields

The model SHALL retain `srcvers`, `protovers` and `osvers` as values comparable segment by segment,
so a version gate never depends on string ordering. A value it cannot parse SHALL be kept verbatim,
reported as unknown for comparisons, and SHALL NOT fail the record.

#### Scenario: Segment-wise comparison

- **WHEN** a receiver advertises `srcvers=354.54.6`
- **THEN** it compares as greater than or equal to `354.54.6` and `354.5`, and as lower than `355`

#### Scenario: Unparsable version

- **WHEN** a receiver advertises a version value that is not a dotted numeric sequence
- **THEN** the raw value is retained, every comparison against it reports unknown, and the rest of the
  record is unaffected

### Requirement: Identity fields

The model SHALL expose the hardware address from `deviceid`, the pairing identity from `pi` falling
back to `psi`, and the advertised public key from `pk` verbatim, keeping a receiver's identity
separate from the address discovery resolved for it.

#### Scenario: Both identities advertised

- **WHEN** a receiver advertises both `pi` and `psi` with different values
- **THEN** the pairing identity is the `pi` value and the `psi` value remains readable from the raw map

#### Scenario: Hardware address only

- **WHEN** a receiver advertises `deviceid` with no pairing identity
- **THEN** the hardware address is reported and the pairing identity is absent

### Requirement: Group fields

The model SHALL expose the group identifier (`gid`), the parent group identifier (`pgid`), the
tight-sync identifier (`tsid`), the group public name (`gpn`) and the leader flags (`igl`, `gcgl`,
`pgcgl`) — the flags as booleans — so multi-room grouping can be decided from a record.

#### Scenario: Group leader

- **WHEN** a receiver advertises `igl=1` with a group identifier
- **THEN** the record reports it as a group leader with that group identifier

#### Scenario: Non-leader member

- **WHEN** a receiver advertises `igl=0` and `gcgl=1`
- **THEN** the record reports it as a non-leader whose group contains a discoverable leader

### Requirement: Tolerant group identifiers

A group identifier value that does not consist of a single identifier — such as the compound form the
ecosystem emits for paired stereo devices — SHALL be reduced to its leading identifier, and a value
that cannot be reduced SHALL be treated as absent, without failing or discarding the rest of the
record.

#### Scenario: Compound group identifier

- **WHEN** a receiver advertises `gid=<identifier>+1+<identifier>` where the leading value equals its
  `tsid`
- **THEN** the record reports the leading identifier as the group identifier and the remaining fields
  are unaffected

#### Scenario: Unreadable identifier

- **WHEN** a receiver advertises a `gid` value that yields no identifier
- **THEN** the group identifier is absent and the record is still reported

### Requirement: Access-control fields

The model SHALL expose the access-control values (`acl`, `act`) and the receiver's required sender
features (`rsf`) verbatim, and SHALL provide a predicate for the documented restricted access-control
value, without discarding values it does not recognise.

#### Scenario: Access restricted

- **WHEN** a receiver advertises `acl=1`
- **THEN** the access-control-restricted predicate is true

#### Scenario: Unrecognised access-control value

- **WHEN** a receiver advertises an `acl` value outside the documented set
- **THEN** the raw value is retained, the restricted predicate is false, and no error is raised

### Requirement: Unknown keys are preserved

The model SHALL retain every TXT key and value it received verbatim — including keys it does not
interpret and the RAOP-specific hints (`cn`, `et`, `sr`, `ss`, `ch`, `pw`, `md`, `am`, `tp`, `da`) —
so callers can read data the model does not name.

#### Scenario: Uninterpreted keys

- **WHEN** a record carries `cn=0,1`, `et=0,3,5` and a key the model does not know
- **THEN** all three are readable from the raw map with their original values

### Requirement: Media capability predicates

The model SHALL expose named predicates for the media capabilities the feature mask carries: video
v1, video v2, photo, slideshow, screen and audio.

#### Scenario: Reference receiver mask

- **WHEN** a receiver advertises the feature mask an AirPlay 2 Apple TV advertises
- **THEN** the video v1, video v2, photo, slideshow, screen and audio predicates are all true

#### Scenario: Empty mask

- **WHEN** a receiver advertises a mask of zero
- **THEN** every media capability predicate is false

### Requirement: Streaming capability predicates with version gates

The buffered-audio predicate SHALL require the buffered-audio feature bit and a `srcvers` at or above
the version where the ecosystem documents buffered audio, and the PTP predicate SHALL require the PTP
feature bit and a `srcvers` at or above the documented version. A gate that cannot be evaluated SHALL
report its capability as unavailable.

#### Scenario: Buffered audio gate satisfied

- **WHEN** a receiver advertises the buffered-audio bit and `srcvers=354.54.6`
- **THEN** the buffered-audio predicate is true

#### Scenario: Buffered audio gate missed

- **WHEN** a receiver advertises the buffered-audio bit and a `srcvers` below that version
- **THEN** the buffered-audio predicate is false

#### Scenario: PTP gate

- **WHEN** a receiver advertises the PTP bit and a `srcvers` at or above the documented PTP version
- **THEN** the PTP predicate is true, and for a `srcvers` below it the predicate is false

#### Scenario: Unknown version with the bit set

- **WHEN** a receiver advertises the buffered-audio bit with no parsable `srcvers`
- **THEN** the buffered-audio predicate is false rather than assumed true

### Requirement: Control and pairing capability predicates

The model SHALL expose named predicates for unified media control, pairing and access control,
transient pairing and AirPlay 2 routing, where the AirPlay 2 predicate is true when either the
unified-media-control or the pairing-and-encryption feature bit the ecosystem checks is set.

#### Scenario: AirPlay 2 capable receiver

- **WHEN** a receiver advertises the unified-media-control bit and the pairing-and-encryption bit
- **THEN** the AirPlay 2, unified-media-control, pairing-and-access-control and transient-pairing
  predicates are true

#### Scenario: Legacy-only receiver

- **WHEN** a receiver advertises no AirPlay 2 feature bit
- **THEN** the AirPlay 2 predicate is false and the media predicates still follow its mask

### Requirement: Conflict resolution between TXT and a later authoritative source

A capability set SHALL be updatable from a later, more authoritative source: the values that source
defines SHALL replace the values derived from TXT instead of being merged or averaged, TXT-only values
SHALL remain readable, and the model SHALL report which source each normalised field came from.

#### Scenario: Authoritative source wins

- **WHEN** a record's TXT advertises a legacy mask and a later authoritative response reports an
  AirPlay 2 mask
- **THEN** the capabilities report the later mask and the TXT-derived values remain readable as
  diagnostics

#### Scenario: Source is reported

- **WHEN** a capability set has been refreshed from an authoritative source
- **THEN** each normalised field reports whether it came from TXT or from the later source
