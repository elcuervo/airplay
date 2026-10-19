# Spec Delta

## ADDED Requirements

### Requirement: Audio Stream Receiver Double Terminates Both Audio Transports

The virtual receiver MUST terminate the negotiated audio transport for the stream type under test: a datagram socket for realtime streams and a stream listener for buffered streams, binding the ports it returns from the stream setup reply. The double MUST decrypt every packet with the session's stream key and the transmitted nonce before reporting it.

#### Scenario: Realtime datagrams are received on the returned port

- **WHEN** a realtime session streams audio
- **THEN** the double receives the datagrams on the data port it returned and decrypts each one successfully

#### Scenario: Buffered frames are read from the returned port

- **WHEN** a buffered session streams audio
- **THEN** the double accepts the connection on the data port it returned and reads length-prefixed frames that decrypt successfully

#### Scenario: The double reports the ports it advertised

- **WHEN** the stream setup reply is generated
- **THEN** the ports named in the reply are the ports the double actually bound

### Requirement: Audio Stream Sink Asserts Framing And Sealing

The audio sink MUST assert, per session and per packet, the decrypted RTP framing: sequence continuity, timestamp advance against the frames carried, constant non-zero SSRC, the payload type the stream definition declared, the marker bit on the first packet of a run only, the trailer layout of authentication tag followed by nonce, and authentication of the timestamp and SSRC as additional authenticated data.

#### Scenario: A conforming session passes every assertion

- **WHEN** a session streams a known PCM fixture
- **THEN** the sink reports no framing, sequencing, sealing or marker assertion failures

#### Scenario: A swapped trailer fails

- **WHEN** a packet is re-ordered so the nonce precedes the tag
- **THEN** the sink fails the run and names the trailer order as the cause

#### Scenario: A packet whose timestamp was altered fails authentication

- **WHEN** a datagram's timestamp is modified in flight
- **THEN** the sink rejects it and fails the run on the authentication assertion

### Requirement: Audio Stream Harness Injects Media Faults

The harness MUST be able to drop, duplicate, delay and reorder datagrams on a realtime session, and to stop reading from a buffered session and resume later, with each fault selectable per session. Faults MUST NOT require the sender process to be restarted and MUST be reported in the run's result.

#### Scenario: Dropped packets trigger retransmission

- **WHEN** the harness drops a run of realtime packets and then requests the missing sequence numbers
- **THEN** the sender answers from its backlog and the sink reports the frames it recovered

#### Scenario: Reordered packets do not break the sink

- **WHEN** datagrams arrive out of order
- **THEN** the sink still reports complete framing and sequencing results, and marks the reordering it injected

#### Scenario: A read pause on a buffered session is not a failure

- **WHEN** the harness stops reading the buffered stream for several seconds and then resumes
- **THEN** the run completes successfully and reports the pause it injected

### Requirement: Audio Stream Harness Asserts Pacing Against The Injected Clock

The harness MUST record the injected clock instant at which each packet is delivered and MUST fail a run when delivery runs further ahead of a frame's deadline than the pacing window, when a frame is delivered after its deadline, or when delivery continues while the clock is held still.

#### Scenario: Delivery inside the window passes

- **WHEN** a session paces a fixture against the injected clock
- **THEN** every packet's delivery instant is within the pacing window before its deadline and the run passes

#### Scenario: A run ahead of the window fails

- **WHEN** the sender is made to deliver as fast as the source allows
- **THEN** the harness fails the run and reports the first packet delivered beyond the window

#### Scenario: A frozen clock stops delivery

- **WHEN** the harness holds the injected clock still after the first packet of a run
- **THEN** no further packet is delivered and the harness reports that fact

### Requirement: Audio Stream Harness Can Time Or Refuse To Time A Session

The receiver double MUST be able to answer timing requests so a session becomes timed, and MUST be able to stay silent so the untimed path is exercised. In its silent mode the double MUST still accept the control session, so the failure under test is the clock exchange alone. The harness MUST also be able to withhold or delay its acceptance of the announced timeline.

#### Scenario: A timed session proceeds

- **WHEN** the double answers timing requests
- **THEN** the session reports timing as established and a scheduled start proceeds

#### Scenario: A silent double surfaces the untimed path

- **WHEN** the double never answers a timing request
- **THEN** the sender reports timing as not established within its bounded window and no content is played early

#### Scenario: A withheld timeline is observable

- **WHEN** the double refuses the announced timeline
- **THEN** the harness reports the refusal and the sender's coded timing outcome

### Requirement: Audio Stream Harness Proves Multi-Room Tolerance

The harness MUST be able to run several receiver doubles on one host as a single group start and MUST fail the run when any two members' first audible instants differ by more than the group tolerance, naming the offending members. The run result MUST report every member's instant.

#### Scenario: An aligned group passes

- **WHEN** every member's first content sample is anchored within the tolerance of the shared instant
- **THEN** the run passes and reports each member's instant

#### Scenario: A skewed group fails

- **WHEN** one member's double delays its content by more than the tolerance
- **THEN** the run fails and names that member and its instant

#### Scenario: Members are not wire-identical

- **WHEN** two members of a group stream identical content
- **THEN** the harness reports that their sequence numbering and RTP offsets differ

### Requirement: Audio Stream Harness Carries Sealing And Timing Conformance Vectors

The harness MUST carry golden vectors that need no receiver: payload sealing cases with fixed key, nonce, additional authenticated data and expected ciphertext with tag, trailer assembly cases that fix the tag-before-nonce order and the transmitted nonce bytes, announcement field layout, and the conversions between the session timeline and NTP-epoch timestamps.

#### Scenario: Sealing vectors reproduce the fixed ciphertext

- **WHEN** the sealing vectors are executed
- **THEN** the produced ciphertext and tag equal the fixed expectations

#### Scenario: Trailer order is pinned by a vector

- **WHEN** the trailer assembly vector is executed
- **THEN** the tag occupies the sixteen bytes before the transmitted nonce, and a swapped assembly fails the vector

#### Scenario: Timeline conversion round-trips

- **WHEN** a timeline position is converted to an NTP-epoch timestamp and back at a known sample rate
- **THEN** the recovered position equals the original within one frame

### Requirement: Audio Stream Harness Covers Codec And Encoder Lanes

The receiver double MUST advertise a configurable codec list and stream-type reply, so the PCM lane, the ALAC lane and the unsupported-codec lane are each exercisable. When no ALAC encoder is available the ALAC lane MUST be reported as skipped with its reason rather than passing silently.

#### Scenario: The codec list drives selection

- **WHEN** the double advertises uncompressed PCM
- **THEN** the run reports the stream definition's compression type and format descriptor for the PCM lane

#### Scenario: An empty codec list fails the lane

- **WHEN** the double advertises no codec the sender can produce
- **THEN** the run reports the sender's coded unsupported-codec error and no audio is received

#### Scenario: A missing encoder is reported, not hidden

- **WHEN** the ALAC lane is requested without an ALAC encoder available
- **THEN** the run reports the lane as skipped with the missing dependency named

### Requirement: Audio Stream Harness Records The Control And Parameter Surface

The receiver double MUST record the commands and parameters it receives per session — the lifecycle commands in order, the volume parameter, DMAP metadata, artwork with its RTP information, and progress — and MUST expose them to tests, including the timing of the first record against the first audio packet.

#### Scenario: Lifecycle order is asserted

- **WHEN** a session plays a fixture
- **THEN** the recorded command order shows the record command before the first audio packet

#### Scenario: The volume parameter is recorded as sent

- **WHEN** a volume change is requested
- **THEN** the recorded parameter carries the value the sender mapped onto the ecosystem curve

#### Scenario: Metadata requests are recorded with their headers

- **WHEN** metadata and artwork are sent
- **THEN** the recorded requests carry the DMAP content type, the tagged fields, the image content type and the RTP information the sender used
