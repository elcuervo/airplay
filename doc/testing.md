# Testing

Tests are split into three lanes:

- `rake test:unit` — configuration, device model, error taxonomy, status events,
  the injectable clock, the DNS codec and the capability model. No sockets, no
  reactor.
- `rake test:protocol` — the in-process virtual receiver and mDNS responder
  double (`airplay-fake-device`) driving sessions and discovery over loopback:
  request recording, timeouts, cancellation, reactor safety, cache expiry,
  goodbyes and fault injection. No Apple TV, system daemon or external network
  required.
- `rake test:hardware` — opt-in validation against a real receiver. Set
  `AIRPLAY_HARDWARE_HOST` (and optionally `AIRPLAY_HARDWARE_PORT`) to run it;
  without them every test skips and the lane succeeds.

`rake` runs unit and protocol. `rake test:all` runs all three.

Set `AIRPLAY_LIVE_DISCOVERY=1` to add the opt-in live-network browse check to the
protocol lane; it skips otherwise.

The virtual receiver and the mDNS responder are dev-only: they are absent from
both runtime gemspecs and are never loaded by the library.
