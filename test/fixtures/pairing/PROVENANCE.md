# Pairing vectors

- `srp_vector.json` — generated with `srptools` (idlesign) using the RFC 5054
  3072-bit group, SHA-512, identity `Pair-Setup`, PIN `3939`, and fixed
  `a`, `b` and salt. The values are the reference implementation's output, not
  this repository's SRP code.
- `hkdf_vectors.json` — generated with Python `cryptography` HKDF-SHA512
  (`length=32`) for the four HAP salt/info pairs.
- `frame_vector.json` — generated with Python `cryptography`
  ChaCha20-Poly1305. The AAD is the two-byte little-endian length prefix and the
  nonce is four zero bytes plus the 8-byte little-endian counter (0).
- `sample.bplist` / `sample.xml.plist` — generated with Python `plistlib` and
  used as an independent reader/writer.
- `tlv8_vector.json` — hand-authored TLV8 bytes; the fragmentation lengths are
  the HAP layout for a 600-byte value.
