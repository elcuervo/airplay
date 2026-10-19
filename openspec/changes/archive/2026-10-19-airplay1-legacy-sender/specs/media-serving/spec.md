# Spec Delta

## Purpose

Serving local media from the sender to the receiver over HTTP, so a device can fetch exactly the
bytes, and byte ranges, it was told to play.

## ADDED Requirements

### Requirement: Local file published as a URL

The sender SHALL publish a local media file to the receiver by returning an absolute HTTP URL addressed to a host the receiver can reach on the sender's network interface, using the port the media server is bound to. The URL MUST NOT contain the file's filesystem path or its name.

#### Scenario: Publishing a local file

- **WHEN** a local video file is published
- **THEN** the returned URL uses the configured advertised address and the media server's bound port, and its path component carries an opaque identifier rather than any part of the file path

#### Scenario: Fetching what was published

- **WHEN** the returned URL is requested
- **THEN** the response body is byte-identical to the file on disk

### Requirement: URL stability within a session

Within one session the same file MUST always map to the same URL, so that repeated publications of one file do not produce distinct URLs. Different files MUST map to different URLs.

#### Scenario: Publishing one file twice

- **WHEN** the same file is published twice in one session
- **THEN** both calls return the identical URL

#### Scenario: Publishing two files

- **WHEN** two different files are published in one session
- **THEN** the two URLs differ

### Requirement: Media server lifecycle

The media server SHALL be started when the first local file is published and stopped when the session closes, and the URL returned MUST remain servable for as long as the session lives. The configured port MUST be used when one is configured; otherwise the port assigned by the operating system MUST be used and the returned URL MUST carry that actual port, without polling for readiness.

#### Scenario: Default port selection

- **WHEN** no port is configured and a local file is published
- **THEN** the returned URL carries the port the server actually bound, and the file is fetchable from it immediately after the call returns

#### Scenario: Port released on session close

- **WHEN** a session that published a file is closed and the same port is bound again
- **THEN** the bind succeeds and the previously published URL no longer serves the file

#### Scenario: No media server for remote playback

- **WHEN** a session only plays remote URLs and pushes pictures
- **THEN** no media server port is bound for that session

### Requirement: Response metadata

A request without a `Range` header SHALL be answered with `200`, `Content-Length` equal to the file's size, `Accept-Ranges: bytes`, and a `Content-Type` derived from the file. The response body MUST be the whole file.

#### Scenario: Whole-file request

- **WHEN** a 4096-byte file is requested without a `Range` header
- **THEN** the answer is `200` with `Content-Length: 4096`, `Accept-Ranges: bytes`, a `Content-Type` matching the file's type, and a 4096-byte body equal to the file

### Requirement: Range requests

A well-formed, satisfiable `Range: bytes=<first>-<last>` request SHALL be answered with `206` and a `Content-Range: bytes <first>-<last>/<size>` header, a `Content-Length` equal to the number of bytes actually served, and exactly those bytes as the body.

#### Scenario: Closed range

- **WHEN** `Range: bytes=100-199` is requested from a 4096-byte file
- **THEN** the answer is `206` with `Content-Range: bytes 100-199/4096`, `Content-Length: 100`, and a 100-byte body equal to bytes 100 through 199 of the file

#### Scenario: Range past the end of the file

- **WHEN** `Range: bytes=4000-9999` is requested from a 4096-byte file
- **THEN** the answer is `206` with `Content-Range: bytes 4000-4095/4096` and a 96-byte body

### Requirement: Open-ended and suffix ranges

A `Range` header whose end is omitted (`bytes=<first>-`) SHALL serve from `<first>` to the end of the file, and a suffix range (`bytes=-<count>`) SHALL serve the last `<count>` bytes, both with `206` and the corresponding `Content-Range`.

#### Scenario: Open-ended range

- **WHEN** `Range: bytes=4090-` is requested from a 4096-byte file
- **THEN** the answer is `206` with `Content-Range: bytes 4090-4095/4096` and a 6-byte body

#### Scenario: Suffix range

- **WHEN** `Range: bytes=-100` is requested from a 4096-byte file
- **THEN** the answer is `206` with `Content-Range: bytes 3996-4095/4096` and a 100-byte body

### Requirement: Unsatisfiable ranges

A `Range` request that cannot be satisfied, including any range requested from an empty file, SHALL be answered with `416` and `Content-Range: bytes */<size>`, and MUST NOT return file bytes.

#### Scenario: First byte beyond the file

- **WHEN** `Range: bytes=5000-` is requested from a 4096-byte file
- **THEN** the answer is `416` with `Content-Range: bytes */4096` and an empty body

#### Scenario: Range on an empty file

- **WHEN** any range is requested from a zero-byte file
- **THEN** the answer is `416` with `Content-Range: bytes */0`

### Requirement: Head requests

A `HEAD` request SHALL return the headers the equivalent `GET` would return, including `Content-Length`, `Accept-Ranges`, `Content-Type` and, for a ranged `HEAD`, `Content-Range` and status `206`, with no response body.

#### Scenario: Whole-file HEAD

- **WHEN** a `HEAD` request is made for a 4096-byte file
- **THEN** the answer is `200` with `Content-Length: 4096` and `Accept-Ranges: bytes`, and the response carries no body

#### Scenario: Ranged HEAD

- **WHEN** a `HEAD` request carries `Range: bytes=100-199`
- **THEN** the answer is `206` with `Content-Range: bytes 100-199/4096` and no body

### Requirement: Unknown published URL

A request for a URL that was never published, or whose session has ended, SHALL be answered with `404` and MUST NOT serve any file from the sender's filesystem.

#### Scenario: Unpublished identifier

- **WHEN** a request is made for an identifier that was never published
- **THEN** the answer is `404` and the body carries no file bytes

#### Scenario: Path traversal attempt

- **WHEN** a request path attempts to reach a filesystem path that was not published
- **THEN** the answer is `404` and no file outside the published set is served

### Requirement: Publishing only readable files

Publishing SHALL accept only an existing, readable, regular file. A missing path, a directory, or an unreadable path MUST fail with a playback-category error and MUST NOT return a URL or start the media server.

#### Scenario: Missing file

- **WHEN** a path that does not exist is published
- **THEN** the call fails with a playback-category error and no URL is returned

#### Scenario: Directory

- **WHEN** a directory path is published
- **THEN** the call fails with a playback-category error and no URL is returned

### Requirement: Content type resolution

The `Content-Type` of a served file SHALL be derived from its file extension through the same type table used to classify media compatibility, and a file with an unknown or missing extension MUST be served as `application/octet-stream` rather than refused.

#### Scenario: Known video extension

- **WHEN** a `.mov` file is served
- **THEN** the answer carries `Content-Type: video/quicktime`

#### Scenario: Unknown extension

- **WHEN** a file whose extension is unknown is served
- **THEN** the answer carries `Content-Type: application/octet-stream` and the file body

### Requirement: Bounded file reads

Serving a request MUST read only the bytes the response carries: a range request for a slice of a file MUST NOT read the whole file, and the read MUST NOT depend on the file fitting in memory.

#### Scenario: Range read is bounded

- **WHEN** a 100-byte range is served from a file larger than the test process's memory budget, read through an instrumented file handle
- **THEN** the instrumented handle reports that no more than the requested 100 bytes were read

### Requirement: Concurrent serving and control

Media serving SHALL proceed concurrently with control traffic on one session: a transfer in progress MUST NOT delay or block a control command, and a control command in progress MUST NOT delay or block a transfer.

#### Scenario: Transfer overlap with a control command

- **WHEN** a range transfer whose body is consumed slowly is in progress and a playback-info command is issued
- **THEN** the control command completes while the transfer is still running and both answer correctly
