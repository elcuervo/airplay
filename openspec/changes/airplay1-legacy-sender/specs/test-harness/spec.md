# Spec Delta

## ADDED Requirements

### Requirement: Legacy receiver mode

The in-process virtual receiver SHALL be startable in a legacy AirPlay 1 mode that answers the legacy control endpoints — `GET /server-info`, `PUT /photo`, `POST /play`, `POST /scrub`, `GET /scrub`, `GET /playback-info`, `POST /rate`, `POST /stop` and `PUT /setProperty` — from a script supplied by the test, and the started instance MUST serve on one host and port for its lifetime.

#### Scenario: Starting the receiver in legacy mode

- **WHEN** a test starts the virtual receiver in legacy mode with a script that answers `GET /server-info` with an XML property list
- **THEN** the receiver is listening on a host and port the test can read, and that request returns the scripted property list

#### Scenario: Legacy control endpoints are answered together

- **WHEN** one legacy-mode instance receives each of the legacy control endpoints in turn
- **THEN** every one of them is answered from the script while the instance keeps its host and port

### Requirement: Legacy receiver mode recordings

Recorded exchanges SHALL expose the request method, the path with its query string, the request headers, and the raw body bytes as received, so a test can assert binary payloads, header values and command targets verbatim.

#### Scenario: Recording a binary photo payload

- **WHEN** a `PUT /photo` whose body contains CRLF pairs and bytes above `0x7F` is received
- **THEN** the recorded exchange carries a body byte-identical to what was sent, together with the recorded `X-Apple-Transition` and `Content-Length` headers

#### Scenario: Reading back recorded targets

- **WHEN** a test issues `POST /rate?value=0` and `PUT /setProperty?forwardEndTime`
- **THEN** the recordings expose the two methods and the two full request targets, including query strings, in the order they were received

### Requirement: Legacy digest challenge control

The legacy mode SHALL be configurable to require digest authentication, to reuse a challenge until a correct credential arrives, and to reject a correct credential on demand, and it MUST report whether a `401` was caused by a missing credential or by a wrong one.

#### Scenario: Challenge then success

- **WHEN** the mode is set to require digest and receives a request with no `Authorization` header followed by one carrying the expected response
- **THEN** it answers `401` with a `WWW-Authenticate: Digest` challenge first, then the scripted success, and reports exactly one request as missing a credential

#### Scenario: Wrong credential is distinguished from a missing one

- **WHEN** the mode receives a request whose `Authorization` header carries a response computed from the wrong password
- **THEN** it answers `401` with a fresh challenge and reports that attempt as having a wrong credential rather than a missing one

#### Scenario: Correct credential rejected on demand

- **WHEN** the mode is configured to reject authentication and receives a request carrying the response it would otherwise accept
- **THEN** it answers `401` without accepting the request
