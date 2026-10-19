# Design

## Context

See `proposal.md` — Why. The constraints that shape this design:

- Today `lib/airplay/browser.rb` browses through the `dnssd` C extension, which needs
  `libavahi-compat-libdnssd` on Linux — absent on this host and in the runtime environment — wraps
  every browse and resolve in `timeout(5)` and converts the timeout into `NoDevicesFound`. The CLI's
  `doctor` repeats the same two wrapped calls. Neither surface can be exercised at all here.
- Devices are stringly: `Browser#get_device_address` returns `"#{host}:#{port}"`, `Devices#add(name,
  address)` and `Device#ip` split that string, and dedupe is by IP. The port is only correct by
  accident of the resolver, and a device that answers on two interfaces collapses or duplicates.
- `Device#text_records=` keeps four keys (`model`, `features`, `macAddress`, `srcvers`) and nothing
  interprets `features`, so the capability data modern receivers publish — the 64-bit mask, status
  flags, pairing keys, group fields — is discarded. Routing in `airplay2-pairing-control` and the
  stream decisions in `raop-audio-stream` and `airplay2-video-playqueue` need exactly that data.
- The runtime is one `Async` reactor per process with a non-blocking rule (`runtime-async-reset`):
  name resolution and every other potentially blocking call must not stall the reactor, and sessions
  own their sockets and tasks. `async-dns` is already in the runtime dependency set.
- Everything must be verifiable without physical hardware, without avahi and without external
  network: the in-process virtual receiver of `test-harness` is the oracle, and it is discovered
  through the harness multicast responder.
- This project is a sender. It consumes discovery and never publishes itself; the responder the
  proposal mentions exists only in the harness.

## Goals / Non-Goals

**Goals:**

- Discovery that runs in-process on the reactor with no native extension and no system daemon, and
  that reports structured records rather than `host:port` strings.
- A capability model that is a small, total function of a TXT map: named predicates, no raise on
  garbage, no data discarded, and refreshable from a later authoritative source.
- Discovery call sites that behave predictably under absence: an empty network is a result, not a
  five-second stall that raises.

**Non-Goals:**

- **mDNS advertisement, service registration and responder behaviour at runtime.** The library never
  publishes, announces or answers a record; the responder lives in the test harness only. The
  proposal's `avahi` is an integration-shell cross-check, never a runtime dependency.
- DNSSD/avahi interop at runtime (`dnssd`, `avahi-browse`, D-Bus, `libdns_sd` compatibility).
- Sleep-proxy, wide-area Bonjour (`_airplay._tcp.<unicast domain>`), AWDL/`_airplay-p2p._tcp`, and
  mDNS probing/conflict resolution for records we own — we own none.
- Pairing, routing policy, playback and the `/info` exchange itself: those belong to
  `airplay2-pairing-control`, which reconciles against this model.

## Decisions

**Pure-Ruby mDNS on the async reactor, not the `dnssd` C extension.** Rationale: `dnssd` requires
`libavahi-compat-libdnssd` (absent on this host and in the runtime), it blocks and needs a thread
bridge that violates the reactor's non-blocking rule, it exposes no TTL or goodbye signal to build a
correct cache on, and no test can run against it here. Alternatives considered: `dnssd` with a
pinned `libdns_sd` shim (a native dependency plus a thread handoff, for the sake of one code path);
`rubydns` (unmaintained, and it is a server framework, not a browser); shelling out to
`avahi-browse --parsable` (a system daemon plus a subprocess parse, untestable without avahi);
`avahi` over D-Bus (same, with a new dependency). Consequence: we own the browse/resolve state
machine, which is what makes the harness double and the fault knobs possible.

**`Resolv::DNS::Message` as the wire codec; our own browse state machine on top.** `async-dns`'s
resolver is unicast-oriented — it dispatches to configured nameservers with ndots/search handling, and
the codec it decodes with is the stdlib's `Resolv::DNS::Message`. We use that codec directly for
encoding queries and decoding datagrams (`#decode`, `#encode`, `#add_question`, `#each_resource`,
and `Resolv::DNS::Resource#ttl`), and write the multicast part ourselves. Alternatives considered: a
hand-rolled parser (reimplements label compression, escaping and rdata lengths — pure risk with no
gain); `Async::DNS::Resolver` per query (no multicast group join, no access to the raw answer's
source address or interface, and a cache keyed by resolution instead of by record TTL, which defeats
the cache decisions below); `dnssd`'s own parser (unavailable). Note `Resource.get_class` returns
`Resolv::DNS::Resource::Generic` for unknown types rather than nil, so forward-compatible answers
decode without special cases and stay available for diagnostics.

**One datagram socket per selected interface and address family, owned by the reactor.** Each socket
joins the multicast group on its interface (IPv4 membership by interface address, IPv6 membership by
interface index), binds port 5353 with address/port reuse so another responder on the host does not
block us, and is served by a receive task that lives in the session task tree; `async-io` wraps
`recvfrom`/`sendmsg` as non-blocking operations, so the loop never stalls the reactor. Queries are
sent from each socket so answers come back scoped to that interface, and each answer is recorded with
the socket it arrived on. Alternatives considered: a dedicated resolver thread with a queue (the
cross-thread handoff this runtime exists to remove, and it makes cancellation and timeouts harder);
a single socket with `IP_MULTICAST_IF` switched per send (multicast-scoped and link-local answers
take the interface from the receiving socket, so the answer/interface correlation is lost);
`IO.select` inside a fiber (same as the reactor does, with worse error handling).

**Cache keyed by service instance, holding each record's own TTL.** An answer's TTL is copied into the
cache entry; a lookup inside the lifetime is served without a query; an expired entry is re-resolved;
a TTL-0 answer (goodbye) removes the instance and its addresses. Expiry is driven by the injectable
clock from the harness, so tests advance time instead of sleeping. Alternatives considered: a fixed
global cache lifetime (wrong for devices that advertise long TTLs and for goodbyes, and untestable
without sleeps); no cache (the current behaviour: every lookup re-browses, which races with playback
startup and makes repeat enumeration non-deterministic); a write-through cache that never expires
(a device that goes away is reported forever).

**Interface selection, deterministic address preference and an advertised-address override.** The
default selection is every up interface that has an address of the family, and tests narrow it to
loopback. One instance answering on several interfaces or families yields one record carrying all
addresses, each with its arriving interface, and the preferred address is chosen deterministically:
an address on a receiving interface, IPv4 before IPv6, link-local last (a link-local address is only
usable with its scope identifier, so it is reported with it). The advertised-address override
replaces the address the library hands to receivers in later session and media exchanges while
sockets keep binding to the resolved local address — the Docker-bridge/NAT case in the ecosystem,
where the reachable address differs from the bound one. Alternatives considered: prefer the SRV
target's name resolution order (hostname order is not a routing decision and can point at an
unreachable family); always prefer IPv6 (the least likely to be reachable on the fleets this project
targets); a caller-supplied interface list only (no sane default for the CLI).

**Public API: `Airplay.devices` over structured records.** `Airplay::Discovery::ServiceRecord`
exposes instance name, service type, SRV target, addresses, port, TXT map, TTL and the capability
model; `Airplay::Discovery::BrowseResult` carries records plus the reason the browse ended;
`Airplay.devices` returns an enumerable of records with lookup by display name and by address or
identifier, and it browses only when the cache is empty and autodiscovery is enabled — which is what
the existing CLI verbs (`Airplay["name"]`, `Airplay.devices.first`) already assume. The legacy
`Device` shape (`name`, `ip`, `type`, `password?`) stays as a thin view over a record so
`airplay1-legacy-sender` can rewrite its body without changing the CLI's shape. Alternatives
considered: keep `host:port` and add parallel fields (two sources of truth for the port, and the
`Devices#add(name, address)` signature keeps inviting a hard-coded 7000); return the raw TXT hash and
let each consumer decode it (duplicates the mask, flag and version grammar in three later changes);
make `Device` the primary type (discovery data would be forced through a playback-era model).

**Capabilities as an immutable, source-tagged value object.** The model keeps the verbatim TXT map and
the parsed mask, flag word and version values, and answers predicate questions. Feature-bit names and
the version gates are taken from the published ecosystem documentation rather than invented here:

| Capability | Condition | Source |
|---|---|---|
| video v1 / video v2 | bit 0 / bit 49 | pyatv `AirPlayFlags`, openairplay `airplay-spec` |
| photo / slideshow / screen / audio | bits 1 / 5 / 7 / 9 | pyatv `AirPlayFlags`, openairplay `airplay-spec` |
| unified media control | bit 38 | pyatv `AirPlayFlags`, `music-assistant/airplay-cli` DESIGN.md |
| buffered audio | bit 40 with `srcvers` ≥ 354.54.6 | `lmcgartland/airplay2-rs` AIRPLAY_2_SPEC.md §2.2, §2.4 |
| PTP | bit 41 with `srcvers` ≥ 366 | `lmcgartland/airplay2-rs` AIRPLAY_2_SPEC.md §2.2, §2.4 |
| pair/access control | bit 46 | pyatv `AirPlayFlags`, `music-assistant/airplay-cli` DESIGN.md |
| AirPlay 2 / pairing-capable | bit 38 or bit 48 | `airplay2-pairing-control` proposal; `music-assistant/airplay-cli` DESIGN.md |
| transient pairing | bit 43 or bit 48 | `lmcgartland/airplay2-rs` AIRPLAY_2_SPEC.md §2.2.1 |
| password / PIN / legacy pairing | `pw=true`, password bit 0x80, PIN bit 0x8, legacy bit 0x200 | pyatv `AirPlayFlags` constants, `is_password_required` |

Where the references disagree (bit 26 versus bit 30 for the unified advertiser info flag, for
example) the model exposes the raw mask so a conflicting consumer can read the bit it cares about,
and the predicates we name are only the ones the ecosystem agrees on. A gate whose version input is
missing or unparsable reports unavailable rather than assumed, matching the "missing mask means
unknown, fall back conservatively" rule both references state. Normalised fields carry their source
(`:txt` or `:authoritative`) so the later `GET /info` reconciliation in `airplay2-pairing-control` can
replace TXT-derived values while the TXT map stays available as diagnostics. Alternatives considered:
a plain Hash of symbols (every consumer re-implements predicates and the gates, and nothing can report
provenance); hard-coding per-model capability tables (needs a hardware fleet we do not have);
rejecting records with malformed values (loses a usable device because one key is garbage).

**The responder double lives in the harness package.** It is a small mDNS responder — bind, join,
answer PTR/SRV/TXT/A/AAAA with configurable instance name, type, target, port, TTL and family,
optionally with faults, and record what it received — shipped in the dev-only fake-device package
introduced by `runtime-async-reset`, extending the multicast responder skeleton that change stands
up. It is the only responder in the system and it is never loaded by the library. Alternatives
considered: stubbing the resolver (exercises none of the codec, socket, interface or cache code —
exactly the failure mode of the tests this change replaces); a real avahi plus service files (a
daemon the runtime must not need, and no per-test fault control); captured pcap replay (brittle,
and it cannot express late SRV, conflicting TXT or IPv6-only answers).

## Risks / Trade-offs

- [Multicast group join fails on virtualized or IGMP-less interfaces] → bind per interface and treat
  "no usable interface" as the transport error of the taxonomy, with loopback as the test default;
  the integration shell exercises a real interface.
- [A second responder on the host already holds 5353] → bind with address and port reuse and never
  bind a privileged ephemeral port for the responder's own answers; a bind failure surfaces as the
  typed transport error rather than an empty result.
- [Our decode path is new code on untrusted datagrams] → the codec is only ever fed by the harness in
  tests and by network peers in production, so malformed and truncated datagrams are rejected with
  the protocol error type and covered by mutation tests.
- [Elapsed-time browse windows are inherently racy on lossy Wi-Fi] → the window is caller-bounded and
  the result reports why it ended, so the CLI can widen it and a caller can re-browse; cache TTLs,
  not the window, decide reuse.
- [Multi-homed hosts picking an address the receiver cannot reach] → per-address interface provenance
  plus the advertised-address override, so the fix is a configuration value rather than a code path.
- [Cache TTL 0 goodbyes removing a still-present device] → removal is scoped to the instance the
  goodbye names, and the harness has a scenario for the subsequent re-advertisement.
- [Instance names carry non-breaking spaces and arbitrary bytes] → normalise whitespace in the
  display name only, and keep the raw service name available for diagnostics.
- [Overlap with the harness skeleton owned by `runtime-async-reset`] → this change only adds the
  DNS-specific behaviours (answers, faults, packet recording) to that package, and the archive order
  keeps the dependency one-directional.

## Open Questions

- The default browse window (currently two seconds) versus Wi-Fi power-save delays: the spec fixes
  only that the window is caller-bounded and reports why it ended, so the default is tuned from the
  opt-in integration cross-check rather than decided here.
- Whether the CLI's `air doctor` shows one device's full raw TXT map behind a flag: a presentation
  choice that does not change the spec, the approach or the task order.
