# Virtual receiver knobs

The protocol lane drives `Airplay::FakeDevice::Receiver`. What it serves is
fixed by `record:`; how it fails is fixed by `faults:` and `pairing:`.

## General faults

`faults:` maps a 1-based request number to a fault (`faults: { 1 => { kind: :status, status: 503 } }`):

- `delay` — sleep `seconds` before answering.
- `status` — answer with `status` instead of the record JSON.
- `auth` — answer `401` with a Digest challenge.
- `truncate` — answer with half the body under the full `content-length`.
- `corrupt` — answer with malformed JSON.

`faults: { connection: :drop }` closes the socket on accept; `:reset` closes it
with `SO_LINGER` so the client observes a reset.

## Pairing mode

Passing `pairing:` switches the receiver into the AirPlay 2 mode. It serves
`POST /pair-setup` and `POST /pair-verify` from scripts and, after pair-verify,
requires AEAD-framed traffic on the same connection.

Options:

- `accept` — `false` rejects every pairing message with the `rejection` TLV.
- `pin` — code the real pair-setup responder accepts for the PIN flow; the
  transient flow always uses `3939`.
- `responses` — per path (`"/pair-setup"`, `"/pair-verify"`) list of per-message
  TLV responses; a Hash is encoded, a String is sent verbatim, a Proc receives
  the decoded items, and `:reject` rejects that message.
- `rejection` — TLV Hash returned on rejection; defaults to the request state
  plus error `0x02`.
- `control_write_key` — key that decrypts the sender's control frames.
- `control_read_key` — key that encrypts the receiver's control frames.
- `info_body` — bytes served for `GET /info`, usually a binary plist.
- `setup_body` — plist served for `POST /setup`; by default the timing
  protocol and port from the request are echoed.
- `demand` — answers every request with `403` and `x-airplay-auth` set to the
  demanded mechanism (`fp-setup`, `auth-setup` or `accessory`).
- `clock` — injectable `FakeClock`; defaults to a fresh one.
- `feedback_interval` — interval the feedback tests assert against.
- `events` — plists written to the reverse event connection after pair-verify.
- `event_target` — `[host, port]` of the reverse event connection.
- `event_write_key` — key that frames the events.
- `faults` — the pairing faults below.

### Pairing faults

- `wrong_pin` — rejects the first pair-setup attempt at the proof message as a
  bad code does; a retry on a fresh connection succeeds.
- `control_401` — answers the first encrypted control request with `401`.
- `corrupt_tag` — flips one bit in the response frame's authentication tag.
- `replayed_counter` — sends the same response frame twice.
- `truncated_frame` — writes a response frame without its tag, then closes.
- `oversized_length` — declares a frame length above the frame maximum, then closes.
- `wedge` — after a rejected pairing, reads and discards every further byte on
  that socket, so a retry must use a new connection.

`Receiver::PAIRING_OPTIONS` and `Receiver::PAIRING_FAULTS` are the source of
truth for this list.
