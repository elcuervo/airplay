# Spec Delta

## ADDED Requirements

### Requirement: Pairing virtual receiver mode

The harness SHALL provide a virtual receiver mode that performs the HAP pairing handshake — transient with the fixed code and PIN/password — and, once pairing completes, serves an authenticated control session in which every subsequent request is framed and encrypted.

#### Scenario: Transient pairing completes with the fixed code

- **WHEN** a test starts the mode and drives a transient pairing exchange
- **THEN** the mode accepts the fixed code and the sender reaches an encrypted control session without hardware or system services

#### Scenario: PIN pairing completes and rejects a wrong code

- **WHEN** a test drives the PIN/password flow once with the accepted code and once with a rejected code
- **THEN** the first exchange yields an encrypted session and the second is answered with the mode's rejection, which the test observes as the sender's authentication failure

#### Scenario: The mode requires encryption after pairing

- **WHEN** a test sends an unframed request after the mode has completed pair-verify
- **THEN** the mode refuses it instead of handling it as a normal control request

### Requirement: Pairing recorded encrypted traffic

The mode SHALL record the traffic of an encrypted exchange and expose, per request, the method, path, headers and the decoded plist body together with the connection it arrived on, so tests can assert on decrypted wire content and ordering.

#### Scenario: Decrypted requests are assertable

- **WHEN** a test completes an encrypted session and asks the mode for the recorded traffic
- **THEN** each recorded request exposes its method, path, headers and decoded plist body

#### Scenario: Ordering and connection are preserved

- **WHEN** a test sends parameters and then a teardown, and later opens a second connection
- **THEN** the recorded order matches the received order and each request carries the connection it arrived on

### Requirement: Pairing fault configuration

The mode SHALL support per-test fault configuration for a rejected pairing (wrong code), a `401` challenge on an authenticated request, a corrupted authentication tag, a replayed frame counter, and a receiver that ignores every byte after a rejection.

#### Scenario: A fault affects only the test that selected it

- **WHEN** one test enables the wrong-code fault while other tests in the same run do not
- **THEN** only that test's pairing is rejected and every other test pairs normally

#### Scenario: A rejected pairing can wedge its socket

- **WHEN** a test enables the wedge fault and the sender retries
- **THEN** the wedged socket receives no further bytes and the retry arrives on a separate recorded connection

#### Scenario: Counter and tag faults close the connection

- **WHEN** a test enables the replayed-counter fault, and separately the corrupted-tag fault
- **THEN** each case closes the connection and the test observes the sender's documented failure rather than a handled request

### Requirement: Pairing framing fault configuration

The mode SHALL additionally support per-test faults on the encrypted transport itself: a frame truncated before its declared length is complete, and a frame header declaring a length above the accepted maximum, so the sender's framing bounds are exercised against a receiver rather than only a unit.

#### Scenario: Truncation mid-frame is selectable

- **WHEN** a test enables the truncated-frame fault
- **THEN** the connection ends inside a frame and the sender's session fails instead of waiting for the rest

#### Scenario: An oversized declared length is selectable

- **WHEN** a test enables the oversized-length fault
- **THEN** the sender fails fast without buffering the declared bytes

### Requirement: Pairing clock injection

The mode SHALL accept an injectable, advanceable clock so that the feedback interval and session timeouts are asserted without sleeping on the wall clock.

#### Scenario: Feedback is asserted without a wait

- **WHEN** a test advances the injected clock by the mode's configured feedback interval
- **THEN** the sender's feedback behaviour at that instant is observable immediately

### Requirement: Pairing credential sandbox

The mode SHALL run against a temporary credential directory supplied through the environment override, and no pairing test SHALL read or write the user's real credential location.

#### Scenario: Pairing writes only inside the sandbox

- **WHEN** a test completes a long-term pairing against the mode
- **THEN** the credential record appears in the temporary directory with the production modes and nothing is written to the user's configuration directory
