# Spec Delta

## Purpose

Encodes and decodes property lists in both the binary (`bplist00`) and XML representations that every modern AirPlay 2 request and response body uses, with deterministic binary output so that exchanged bytes can be asserted directly.

## ADDED Requirements

### Requirement: Binary plist decoding

The sender SHALL decode binary property lists including the header, object table, offset table and trailer, supporting null, boolean, signed and unsigned integers of one, two, four and eight bytes, 32-bit and 64-bit reals, dates, data, ASCII strings, UTF-16 big-endian strings, arrays and dictionaries.

#### Scenario: A representative document decodes completely

- **WHEN** a binary property list containing a string, an integer, a real, a date, a data value, a boolean, an array and a nested dictionary is decoded
- **THEN** every value is yielded with its original type and content

#### Scenario: Non-ASCII strings decode correctly

- **WHEN** a binary property list containing a UTF-16 big-endian string with characters outside ASCII is decoded
- **THEN** the decoded string equals the original text

### Requirement: Binary plist encoding

The sender SHALL encode the same value set into a valid `bplist00` document whose header, object table, offset table and trailer a third-party binary plist reader accepts.

#### Scenario: Encoded output is readable by the fixture decoder

- **WHEN** a document is encoded and the result is read with an independent binary plist reader
- **THEN** the reader yields values equal to the input

#### Scenario: Containers nest to arbitrary depth

- **WHEN** an array containing a dictionary containing an array is encoded
- **THEN** the encoded document decodes back to the same nested structure

### Requirement: Deterministic binary encoding

Encoding the same logical value twice SHALL produce byte-identical output, with object ordering fixed by the encoder and independent of runtime hash iteration order.

#### Scenario: Repeated encoding is byte-identical

- **WHEN** a dictionary with many keys is encoded twice in separate processes
- **THEN** the two byte strings are identical

### Requirement: XML plist codec

The sender SHALL encode and decode the XML property list representation for the same value model, and a value round-tripped through XML SHALL compare equal to the original value.

#### Scenario: XML fixtures round-trip

- **WHEN** an XML property list fixture containing an array, a dictionary, a date and a data value is decoded and re-encoded
- **THEN** decoding the re-encoded document yields a value equal to the first decode

### Requirement: Date representation

Property list dates SHALL be handled as absolute instants counted in seconds from 2001-01-01T00:00:00Z, and the binary and XML representations SHALL convert to and from the same instant without loss of sub-second precision beyond what the representation carries.

#### Scenario: A date survives both representations

- **WHEN** a known instant is encoded in the binary representation and in the XML representation and both are decoded
- **THEN** both decode to the same UTC instant that the golden fixture records

### Requirement: Malformed plist handling

Input that is truncated, declares more objects than it contains, uses an unsupported object marker or exceeds the maximum accepted document size MUST raise a specific decoding error instead of returning partial values or consuming input without bound.

#### Scenario: A truncated document raises an error

- **WHEN** a binary property list is decoded with its tail removed
- **THEN** a specific decoding error is raised and no partial value is returned

#### Scenario: An unsupported marker raises an error

- **WHEN** a document uses an object marker the codec does not implement
- **THEN** a specific decoding error naming the marker is raised

### Requirement: Reviewable plist examples

The change SHALL keep a reviewable Ruby sample for the plist value model, so a reviewer can
see how requests are built and decoded.

```ruby
value = {
  "session" => "UUID",
  "volume" => -15.0,
  "streams" => [{ "type" => 96 }],
  "when" => Time.utc(2026, 10, 19),
  "data" => Airplay::Plist::Data.new("\x00\x01".b)
}

bytes = Airplay::Plist.dump(value) # bplist00
Airplay::Plist.load(bytes)         # => the same value model

Airplay::Plist.load(truncated)     # raises Airplay::Plist::DecodeError
```

#### Scenario: Values survive a round trip

- **WHEN** a request body is built with the value model and encoded
- **THEN** decoding it yields the same values, with dates as absolute instants and data as bytes

