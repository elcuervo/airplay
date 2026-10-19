# Proposal

## Why

Discovery is the entry point of every workflow, and today it is both unrunnable and
untestable: it depends on the `dnssd` C extension, which needs `libavahi-compat-libdnssd` on
Linux — absent on this host — and it resolves devices through a `timeout(5)` + `break` loop
whose results cannot be asserted without a live network (`lib/airplay/browser.rb`,
`lib/airplay/cli/doctor.rb`). It also throws away the capability data modern receivers
publish in their TXT records (64-bit `features` as `0xLOW,0xHIGH`, `srcvers`, `protovers`,
`pk`, `gid`, `flags`), which is precisely what decides whether a device speaks legacy AirPlay,
RAOP or AirPlay 2. Without a real discovery and capability model, every routing decision
downstream is guesswork.

## What Changes

- Replace `dnssd` with a pure-Ruby mDNS implementation on the async reactor: multicast queries
  and responses on `224.0.0.251:5353` (IPv4) and `ff02::fb:5353` (IPv6), PTR → SRV → TXT →
  A/AAAA resolution, TTL-aware cache, interface selection and an advertised-address override.
- Browse both service types: `_airplay._tcp.` and `_raop._tcp.` (the latter carries RAOP
  fallback hints: `cn`, `et`, `pw`, `sr`, `ss`, `ch`, `am`, `vs`, `vn`, `ft`, `sf`).
- Normalize the TXT record into a typed model: `features` decoded as one 64-bit integer
  (accepting `0xLOW,0xHIGH` and `ft`), status flags (`flags`/`sf`), version strings, identity
  keys (`deviceid`, `pi`, `psi`, `pk`), group fields (`gid`, `pgid`, `tsid`, `igl`, `gcgl`)
  and access-control fields, with unknown keys preserved rather than dropped.
- Expose named capabilities instead of raw bits (audio, video v1/v2, photo, slideshow, screen,
  buffered audio, PTP, unified media control, pairing/access control, transient pairing,
  volume, mute), including the `srcvers` gates that qualify some of them.
- Replace the stringly `"host:port"` device address with structured service records, so the
  port is always taken from SRV and never assumed to be 7000.
- Keep `air doctor` as the human-facing discovery diagnostic, now reporting the parsed
  capability model per device rather than raw TXT dumps.
- Explicitly not in this change: no control-plane changes, no pairing, no playback; and no
  mDNS *advertisement* — this project is a sender and never publishes a service on the network
  (the responder only exists inside the test harness).

## Capabilities

### New Capabilities
- `service-discovery`: browsing, resolving, caching and selecting AirPlay/RAOP services over
  mDNS without external system services, including multi-interface and IPv4/IPv6 behaviour.
- `device-capabilities`: the typed capability model derived from TXT records — 64-bit feature
  mask, status flags, version gates, identity and group fields — that routing and playback
  decisions read.

### Modified Capabilities
- None yet: `service-discovery` and `device-capabilities` are introduced here, and later
  changes (`airplay2-pairing-control`, `raop-audio-stream`) consume them.
- `test-harness` (introduced by the sibling change `runtime-async-reset`): this change contributes
  an `ADDED` delta only — the mDNS responder double and its discovery fault knobs — under the same
  capability path, with requirement names prefixed `Discovery ` so they cannot collide with the
  requirements other changes add. No base spec exists under `openspec/specs/` until the owning
  change is archived, so no `MODIFIED` delta is written.

## Impact

- Replaces `lib/airplay/browser.rb` and reworks `lib/airplay/devices.rb` and
  `lib/airplay/cli/doctor.rb`; the `dnssd` dependency and the `NoDevicesFound`-by-timeout
  behaviour go away.
- Adds the TXT/capability model that `route-selection` in `airplay2-pairing-control` and the
  stream decisions in `airplay2-video-playqueue` and `raop-audio-stream` depend on.
- Harness slice: an in-process mDNS responder double that advertises arbitrary devices and
  capability masks, plus fault knobs (late SRV, conflicting TXT, IPv6-only, packet loss),
  all runnable without avahi or a real network.
- `nix develop` provides `avahi` in the integration shell for cross-checking our results
  against a reference resolver; it is never a runtime dependency.
