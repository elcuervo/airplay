# Spec Delta

## ADDED Requirements

### Requirement: Remote URL handed to the queue item

For a local file, the URL handed to the receiver in the queue item MUST be an absolute URL served by
the sender's media server, addressed on an interface the receiver can reach, and MUST NOT be a
loopback or unserved URL.

#### Scenario: Local file

- **WHEN** a local file is played on a modern route
- **THEN** the item's URL host is the address the session is using with that receiver, and a request for that URL is served by the media server

#### Scenario: Address the receiver cannot reach

- **WHEN** the media server can only be addressed on a loopback address
- **THEN** the play fails with a typed failure naming the unusable address instead of handing the receiver a URL it cannot fetch

### Requirement: Remote URL is served for the session's lifetime

The handed URL MUST remain valid and served from the moment the item is inserted until the session's
playback ends or the session is torn down, and the receiver's repeated or concurrent requests for it
MUST NOT require a new URL.

#### Scenario: Repeated requests

- **WHEN** the receiver requests the handed URL several times, including byte ranges, while the item plays
- **THEN** every request is served from the same URL and the URL in the queue item is unchanged

#### Scenario: Withdrawn at teardown

- **WHEN** the session is torn down
- **THEN** a request for the previously handed URL is no longer served

### Requirement: Remote URL passes remote media through unchanged

When the media is a remote URL, the sender MUST hand that URL to the receiver unchanged, and MUST NOT
proxy, rewrite or pre-fetch it.

#### Scenario: Remote playlist

- **WHEN** a remote playlist URL is played on a modern route
- **THEN** the item carries the same URL in the same scheme and spelling, and the sender fetches none of it

### Requirement: Remote URL declares its transport security

The queue item MUST declare whether the handed URL is TLS-secured according to its scheme, so the
receiver fetches it the way the scheme requires.

#### Scenario: Both schemes

- **WHEN** a TLS-schemed URL and a plain-schemed URL are each played
- **THEN** the item's transport-security field is set for the first and clear for the second

### Requirement: Remote URL item declares file media

The inserted item MUST declare the media kind the profile records for a file playback, so the receiver
treats the handed URL as media rather than as an unknown item.

#### Scenario: Item media kind

- **WHEN** a URL or a local file is played on a modern route
- **THEN** the item's media-kind field carries the value the profile's recorded shape uses

### Requirement: Remote URL is served with the file's content type

For a local file, the media server MUST answer the receiver with the file's content type and its
length, and a ranged request MUST be answered as the capability's range contract requires.

#### Scenario: Content type and ranges

- **WHEN** the receiver requests a local video file by its handed URL, with and without a byte range
- **THEN** the responses carry the file's content type and length, and the ranged request is answered with partial content and a content range

### Requirement: Remote URL requires no extra request headers

The media server MUST serve the handed URL for a standard HTTP/1.1 request and MUST NOT require any
request header the receiver cannot be expected to send.

#### Scenario: Plain request

- **WHEN** a request for the handed URL arrives with no header beyond the standard request set
- **THEN** it is served successfully rather than rejected
