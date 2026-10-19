# Spec Delta

## Purpose

Streams audio to AirPlay/RAOP receivers: session setup, RTP transport with per-packet encryption, codec selection bounded by the receiver's advertisement, volume, and the audio transport and metadata surface.

## ADDED Requirements

### Requirement: Audio Session Setup Runs In Two Phases

Audio setup MUST run in two phases on a session that already holds an authenticated control connection. Phase one establishes session identity and timing negotiation, advertising our timing port and protocol; phase two defines the audio stream. Phase two MUST NOT be sent before phase one has been acknowledged, and a rejection in either phase MUST fail the audio binding with a coded error rather than leaving a half-started stream.

#### Scenario: Phase one precedes phase two

- **WHEN** a session binds an audio stream
- **THEN** the phase-one request carrying identity and timing fields is acknowledged before the phase-two stream definition is sent

#### Scenario: Rejected phase one leaves no stream

- **WHEN** phase one is rejected by the receiver
- **THEN** the session reports a coded protocol error and no audio packet is ever sent on the session

#### Scenario: A rejected phase two leaves the session usable

- **WHEN** phase two is rejected
- **THEN** the audio binding fails with a coded error and the session's control channel remains usable for a retry

### Requirement: RAOP-Compat Sessions Announce The Stream Before Setup

On a RAOP-compat route the sender MUST announce the stream with an SDP description naming the audio format and payload type before setup, and MUST perform setup with a transport header that advertises our control and timing ports. The receiver's data, control and timing ports MUST be taken from the setup reply.

#### Scenario: Announcement precedes setup

- **WHEN** a RAOP-compat session starts audio setup
- **THEN** the SDP announcement naming the payload type and audio format is acknowledged before the setup request is sent

#### Scenario: Receiver ports come from the reply

- **WHEN** the setup reply names a data port, a control port and a timing port
- **THEN** the session sends audio to the replied data port and announcements to the replied control port

### Requirement: Phase One Declares Session Identity And Timing

Phase one MUST carry the sender identity in device-ID and MAC form, a freshly generated session UUID, and the timing negotiation fields naming our timing responder's UDP port and the timing protocol the session can actually serve. It MUST NOT contain audio stream definitions, codec choices or stream keys.

#### Scenario: Phase-one request shape

- **WHEN** phase one is sent
- **THEN** it carries the device ID, MAC address, session UUID and our timing port and timing protocol

#### Scenario: No stream definition leaks into phase one

- **WHEN** the phase-one body is inspected
- **THEN** it contains no `streams` entry, codec field or stream key

### Requirement: Phase Two Defines The Audio Stream

Phase two MUST define exactly one stream entry carrying the payload type, compression type, audio format descriptor, sample rate, samples per frame, our control port, and the stream key. The receiver's data and control ports MUST be read from the reply by key, never by position, because receivers vary the order in which they serialize them.

#### Scenario: Stream-definition fields

- **WHEN** phase two is sent for a realtime PCM stream
- **THEN** the stream entry names the payload type, compression type, audio format descriptor, sample rate, samples per frame and control port

#### Scenario: Ports are read by key

- **WHEN** the receiver's reply serializes its control port before its data port
- **THEN** the session still binds audio to the data port and announcements to the control port

#### Scenario: A reply without a data port fails the setup

- **WHEN** the phase-two reply carries no data port
- **THEN** the session fails the audio binding with a coded protocol error instead of sending audio to a default port

### Requirement: Stream Type Follows The Advertised Buffered-Audio Capability

The stream definition MUST declare buffered audio when the receiver advertises buffered-audio support and realtime audio otherwise. The declared payload type MUST be the payload type of every audio packet in the session, and the session MUST NOT change payload type mid-stream.

#### Scenario: Buffered-capable receiver

- **WHEN** the receiver advertises buffered-audio support and the route selects buffered audio
- **THEN** phase two declares the buffered payload type and every audio packet on the session carries it

#### Scenario: Receiver without buffered audio

- **WHEN** the receiver does not advertise buffered-audio support
- **THEN** phase two declares the realtime payload type, whatever the caller requested

#### Scenario: Packet payload type matches the declaration

- **WHEN** the session is streaming
- **THEN** no audio packet carries a payload type other than the one phase two declared

### Requirement: Realtime Latency Bounds Are Declared Only For Realtime Streams

The latency bounds (`latencyMin` and `latencyMax`, expressed in frames) MUST be declared in the stream definition of realtime streams only. A buffered stream definition MUST NOT carry them, because a receiver applies such bounds as an extra render delay on top of the buffered anchor.

#### Scenario: Realtime definition carries its bounds

- **WHEN** the session sets up a realtime stream
- **THEN** the stream entry carries a minimum and a maximum latency in frames within the standard two-second window

#### Scenario: Buffered definition omits the bounds

- **WHEN** the session sets up a buffered stream
- **THEN** the stream entry carries no latency bounds

### Requirement: Codec Selection Is Bounded By The Receiver Advertisement

The sender MUST send a codec the receiver advertises in its codec list. Uncompressed PCM MUST be preferred, declared as compression type 1 with the PCM audio format descriptor, 44100 Hz and 352 frames per packet. ALAC MUST be selected only when the receiver advertises it and an encoder is available; when neither path is available the session MUST fail with a coded error instead of sending a codec the receiver never advertised.

#### Scenario: PCM is chosen when advertised

- **WHEN** the receiver advertises uncompressed PCM
- **THEN** the stream definition declares compression type 1 and the PCM format descriptor at 44100 Hz with 352 frames per packet

#### Scenario: ALAC is the second path

- **WHEN** the receiver does not advertise PCM, advertises ALAC, and an ALAC encoder is available
- **THEN** the stream definition declares ALAC and the packets carry ALAC frames

#### Scenario: No usable codec fails loudly

- **WHEN** the receiver advertises neither PCM nor any codec the sender can produce
- **THEN** the session fails with a coded unsupported-codec error and sends no audio

### Requirement: Audio Packets Manage Sequence, Timestamp And SSRC

Every audio packet MUST carry a 16-bit sequence number advancing by one per packet, a 32-bit RTP timestamp advancing by the number of frames the packet carries, and a session-constant, non-zero SSRC. The RTP timestamp MUST express the frame's position on the session timeline, not the wall-clock instant of the send.

#### Scenario: Sequence advances by one

- **WHEN** the harness sink receives a run of audio packets
- **THEN** each sequence number is exactly one greater than the previous, modulo the 16-bit range

#### Scenario: Timestamps advance by the frames carried

- **WHEN** consecutive packets carry 352 frames each
- **THEN** the difference between consecutive RTP timestamps is 352

#### Scenario: SSRC is stable

- **WHEN** the harness sink receives every packet of a session
- **THEN** all packets carry the same non-zero SSRC

### Requirement: Audio Payloads Are Sealed With The Stream Key

Every audio payload MUST be sealed with the authenticated encryption the AirPlay 2 audio path uses, keyed by the session's stream key, with additional authenticated data covering the packet's RTP timestamp and SSRC, and with the packet's nonce transmitted in the packet. A packet on the wire MUST be the RTP header, then the ciphertext, then the authentication tag, then the transmitted nonce.

#### Scenario: Sink verifies the tag

- **WHEN** the harness sink decrypts an audio packet with the session's stream key and the transmitted nonce
- **THEN** authentication succeeds and the recovered payload equals the frame the sender read from its source

#### Scenario: AAD covers timestamp and SSRC

- **WHEN** a packet's RTP timestamp or SSRC is altered in flight
- **THEN** authentication of the packet fails at the sink

#### Scenario: An altered payload is rejected

- **WHEN** one ciphertext byte is flipped in flight
- **THEN** authentication fails and the sink discards the packet

### Requirement: The Packet Nonce Is Deterministic Per Packet

The transmitted nonce MUST be derived from the packet's position in the session, so that re-sending a packet is byte-identical to its original and no nonce is ever reused for a different payload under the same stream key. Realtime streams MUST derive it from the RTP sequence number; buffered streams, whose sequence numbers wrap within a long session, MUST derive it from a per-packet counter.

#### Scenario: A resent packet is byte-identical

- **WHEN** a realtime packet is answered to a retransmission request
- **THEN** the bytes sent equal the original packet byte for byte, nonce included

#### Scenario: Nonces never repeat within a session

- **WHEN** the harness sink collects every transmitted nonce of a session
- **THEN** no nonce value occurs twice

### Requirement: Realtime Audio Is Sent As Datagrams To The Negotiated Data Port

Realtime audio MUST be sent as datagrams to the receiver's negotiated data port, with the marker bit set on the first packet after the session is recorded and on the first packet after a flush. The sender MUST NOT send to a hardcoded port and MUST NOT block the runtime's reactor on a datagram send.

#### Scenario: Datagrams land on the negotiated port

- **WHEN** the receiver returns data port N for the stream
- **THEN** every audio datagram is addressed to port N

#### Scenario: The restart marker is set once per timeline

- **WHEN** content starts after the session is recorded
- **THEN** the first audio packet of the run has its marker bit set and the following packets do not

### Requirement: Buffered Audio Uses The Length-Prefixed Stream Transport

Buffered audio MUST be sent over a stream connection to the receiver's negotiated data port, each packet framed with a two-byte big-endian length that counts the whole frame and carrying the buffered payload type with the same sealing trailer as realtime audio. A buffered session MUST send no time announcements and MUST answer no retransmission requests, because the stream transport is the reliability layer.

#### Scenario: Frames parse with the self-counting prefix

- **WHEN** the harness sink reads the buffered stream
- **THEN** each frame's leading length equals the number of bytes in that frame including the length field

#### Scenario: No announcements and no retransmission on a buffered session

- **WHEN** a buffered session plays content and the sink requests one lost packet
- **THEN** the session has sent no announcement packet and answers no retransmission request

### Requirement: A Buffered Sender Sustains Receiver Read Pauses

A buffered receiver pulls its stream on its own schedule, so a full send buffer or a long pause in reads MUST NOT be treated as a fault: the sender MUST hold unwritten bytes and resume when the connection drains, MUST NOT tear the session down, and MUST NOT let a send deadline end an otherwise healthy session.

#### Scenario: Read pause is not a failure

- **WHEN** the harness sink stops reading for several seconds and then resumes
- **THEN** the session reports no error and continues writing from where it stopped

#### Scenario: Held bytes drain in order

- **WHEN** the sink resumes reading after a pause
- **THEN** the frames it reads are contiguous and in sequence order, with no gap

### Requirement: Lost Realtime Packets Are Answered From A Bounded Backlog

The sender MUST answer retransmission requests received on the session's control port with the original packet, byte for byte, out of a bounded backlog of recently sent packets, and MUST NOT answer a request for a sequence number the backlog no longer holds.

#### Scenario: A held packet is resent

- **WHEN** the receiver requests the sequence number of a packet still in the backlog
- **THEN** the session sends that packet again, byte for byte identical to the original

#### Scenario: An evicted packet is not faked

- **WHEN** the receiver requests a sequence number that has left the bounded backlog
- **THEN** the session sends nothing for it and reports the miss

#### Scenario: The backlog is bounded

- **WHEN** a session has streamed far more packets than the backlog holds
- **THEN** the retained packet count never exceeds the configured bound

### Requirement: Content Is Sent Only After The Session Is Recorded

The sender MUST send the record command before the first audio packet and MUST NOT send audio when the record command is rejected; a rejected record MUST fail the stream with a coded error.

#### Scenario: Record precedes content

- **WHEN** a stream starts playing
- **THEN** the record command is acknowledged before the first audio packet leaves the sender

#### Scenario: A rejected record sends no audio

- **WHEN** the receiver rejects the record command
- **THEN** no audio packet is sent and the session reports a coded playback error

### Requirement: Flush Discards Receiver-Side Positions

A flush MUST tell the receiver which positions to discard, using the flush verb of the session's stream type: the realtime flush carrying the last sent sequence number and RTP timestamp, the buffered flush carrying the buffered stream's equivalent sequence and timestamp. After a flush the sender MUST NOT rely on any position the receiver has discarded.

#### Scenario: Realtime flush carries the positions

- **WHEN** a realtime session flushes
- **THEN** the flush request names the last sent sequence number and RTP timestamp

#### Scenario: Buffered flush uses the buffered verb

- **WHEN** a buffered session flushes
- **THEN** the buffered flush verb is sent with the buffered stream's last sequence number and timestamp

### Requirement: Teardown Releases The Stream

Teardown MUST stop content, send the teardown command to the receiver, close the audio transport and the timing responder, release the session's ports, and forget the stream key. A failed or unanswered teardown command MUST NOT leave the local sender running.

#### Scenario: Ports are released

- **WHEN** a session tears down and another session immediately binds the same local ports
- **THEN** the second bind succeeds

#### Scenario: Teardown failure still closes locally

- **WHEN** the teardown command is rejected or unanswered
- **THEN** the local transport and responder are closed and the session reports the coded error

### Requirement: Volume Is Applied On The Ecosystem Curve

A requested volume percentage MUST be mapped linear-in-dB onto the ecosystem's −30 dB to 0 dB range, with zero percent sent as the ecosystem's muted value, and MUST be sent to the receiver as the volume parameter. The sender MUST NOT apply the gain locally: audio is transmitted at full scale.

#### Scenario: Full and mid volume map onto the curve

- **WHEN** volume 100 is requested
- **THEN** the parameter value is 0 dB, and a request for 50 sends −15 dB

#### Scenario: Zero volume mutes

- **WHEN** volume 0 is requested
- **THEN** the session sends the muted parameter value rather than a finite attenuation

#### Scenario: No local gain is applied

- **WHEN** volume is changed mid-stream
- **THEN** subsequent packets carry identical ciphertext for identical frames, and only the parameter request differs

### Requirement: Text Metadata Is Sent As DMAP Tags

Title, album and artist MUST be sent as DMAP-tagged fields inside a DMAP metadata container with the DMAP content type, and MUST be sent only to receivers that advertise text metadata support. A receiver that does not advertise it MUST receive no metadata request.

#### Scenario: DMAP request shape

- **WHEN** metadata is sent for a track with a title, album and artist
- **THEN** the request carries the DMAP container content type and one tagged field per attribute

#### Scenario: Unadvertised metadata is not sent

- **WHEN** the receiver advertises no text metadata support
- **THEN** no metadata request is sent on that session

### Requirement: Artwork And Progress Ride The Parameter Surface

Artwork MUST be sent as an image parameter request naming the current RTP information, and progress MUST be sent as a start/now/end parameter expressed on the session timeline. Each MUST be sent only when the receiver advertises that metadata type.

#### Scenario: Artwork carries the RTP information

- **WHEN** artwork is sent during playback
- **THEN** the request carries the image content type and the session's current sequence number and RTP timestamp

#### Scenario: Progress is expressed on the session timeline

- **WHEN** progress is sent for a track of known duration
- **THEN** the start, now and end values are RTP positions on the session timeline, with now advancing as the stream plays

#### Scenario: Progress is skipped when unsupported

- **WHEN** the receiver advertises no progress support
- **THEN** no progress parameter is sent on that session

### Requirement: The Session Exposes A Uniform Transport Surface

A bound audio session MUST expose play, pause, resume, stop, seek and volume through the same session surface the video path uses, so the command surface can drive both without protocol knowledge. Pause MUST stop content without tearing the session down, and resume MUST anchor before it sends.

#### Scenario: Pause keeps the session

- **WHEN** play is followed by pause and then resume
- **THEN** the control session and its transport stay bound across the pause, and content flows again after the resume

#### Scenario: Seek flushes before playing

- **WHEN** a seek is requested while playing
- **THEN** the session flushes the receiver's positions and continues from the sought position on a fresh anchor

### Requirement: Streaming Failures Use The Shared Error Taxonomy

Every audio failure — an unsupported codec, an untimed receiver, a rejected command, a transport error, a failed seal or a refused start — MUST surface as a coded error from the shared taxonomy (connection, protocol, authentication, playback, timing) and MUST NOT be swallowed into a silent stop.

#### Scenario: Unsupported codec is coded

- **WHEN** no codec the receiver advertised can be produced
- **THEN** the caller receives a coded error from the protocol or playback class naming the unsupported codec

#### Scenario: Transport failure is coded

- **WHEN** the audio transport fails mid-stream
- **THEN** the caller receives a coded connection error and the session reports its state as stopped rather than playing
