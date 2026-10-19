## Discovery

Discovery is pure Ruby and runs on the process reactor. It browses multicast DNS for
`_airplay._tcp.local.` and `_raop._tcp.local.`, resolves `PTR -> SRV -> TXT -> A/AAAA`,
and returns structured records. The library never advertises, announces or answers a
service; it only sends queries and consumes answers.

### Browse

```ruby
results = Airplay.browse(window: 2.0)

results.reason  # => :data_available, :window_elapsed or :cancelled
results.records.each do |record|
  puts "#{record.display_name} #{record.host}:#{record.port}"
end
```

The port always comes from the SRV answer; discovery never assumes 7000. The record exposes
the instance name, display name, service type, SRV target, addresses with their interface,
TXT map, TTL and capability model as separate values.

```ruby
record = results.records.first
record.name          # => "Living Room"
record.display_name  # => "Living Room" (the part after "@" for RAOP)
record.identifier    # => "AA:BB:CC:DD:EE:FF" (RAOP identifier or TXT deviceid)
record.service_type  # => "_airplay._tcp.local."
record.target        # => "living-room.local."
record.port          # => 7000
record.addresses     # => [#<Address ip="192.0.2.10" family=:ipv4 interface="en0">]
record.txt           # => {"deviceid"=>"...", "features"=>"..."}
```

### Address selection

One instance answering on several interfaces yields one record carrying every address.
The preferred address is deterministic: an address on a receiving interface, IPv4 before
IPv6, link-local last. Link-local addresses keep their scope identifier (`fe80::1%en0`).

The advertised address can be overridden without changing the socket's local bind address:

```ruby
Airplay.configure { |config| config.advertised_address = "203.0.113.10" }
record.advertised_address # => "203.0.113.10"
```

### Capabilities

The TXT map is normalized into a capability model. Unknown keys and RAOP hints stay
readable in `record.txt`.

```ruby
capabilities = record.capabilities
capabilities.mask                 # => 0x0008030040000a00
capabilities.video?               # bit 0
capabilities.video_v2?            # bit 49
capabilities.photo?               # bit 1
capabilities.slideshow?           # bit 5
capabilities.screen?              # bit 7
capabilities.audio?               # bit 9
capabilities.unified_media_control? # bit 38
capabilities.pairing?             # bit 46
capabilities.transient_pairing?   # bit 43 or 48
capabilities.airplay2?            # bit 38 or 48
capabilities.buffered_audio?      # bit 40 and srcvers >= 354.54.6
capabilities.ptp?                 # bit 41 and srcvers >= 366
capabilities.password_required?   # pw=true or status bit 0x80
capabilities.pin_required?        # status bit 0x8
capabilities.legacy_pairing?      # status bit 0x200
capabilities.restricted_access?   # acl=1
```

Feature and gate values come from pyatv's `AirPlayFlags`, the openairplay
`airplay-spec`, and `lmcgartland/airplay2-rs` (`AIRPLAY_2_SPEC.md`). Where the references
disagree, the raw mask stays available and the model names only the agreed predicates.
A missing or malformed value is reported as unknown, never raised; a version gate with an
unknown `srcvers` reports unavailable.

A later authoritative source can replace the values it defines while the original TXT map
stays readable:

```ruby
live = record.capabilities.refresh("features" => "0x40000a00,0x80300", "srcvers" => "354.54.6")
live.source(:mask) # => :authoritative
live.txt["features"] # => the original TXT value
```

### Cache and bounded windows

Records are cached for the TTL of the answer that produced them. A browse inside the TTL
is served from the cache without sending a query; expiry re-queries; a TTL-0 goodbye
removes the instance. Browsing is always caller-bounded and never raises for an empty
network:

```ruby
result = Airplay.browse(window: 0.5)
result.records # => []
result.reason  # => :window_elapsed
```

An unusable interface is a different outcome and raises the runtime's transport error:

```ruby
begin
  Airplay::Discovery::Browser.new(interfaces: ["nope0"]).browse(window: 0.2)
rescue Airplay::TransportError => error
  error.code # => :interface_unavailable
end
```

### CLI

```sh
air list    # one line per discovered device
air doctor  # name, type, host, port, addresses, capabilities and TXT
```

`air list` prints nothing and exits 0 on an empty network. `air doctor` exits non-zero
when discovery fails with a typed error.
