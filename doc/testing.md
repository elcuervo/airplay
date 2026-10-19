# Testing

Tests are split into three lanes:

- `rake test:unit` — configuration, device model, error taxonomy, status events,
  the injectable clock, the DNS codec and the capability model. No sockets, no
  reactor.
- `rake test:protocol` — the in-process virtual receiver and mDNS responder
  double (`airplay-fake-device`) driving sessions and discovery over loopback:
  request recording, timeouts, cancellation, reactor safety, cache expiry,
  goodbyes and fault injection. The receiver also runs a legacy mode (scripted
  `server-info`, `photo`, `play`, transport, `playback-info` and `setProperty`
  responses), a digest-challenge mode with configurable realm, nonce, `qop` and
  credentials, photo-integrity assertions over the received body, and the
  connection knobs (close after response, delayed bodies). No Apple TV, system
  daemon or external network required.
- The media server's byte-range contract is driven through a raw range client
  (`test/support/range_client.rb`), with 200/206/416/HEAD fixtures.
- `rake test:hardware` — opt-in validation against a real receiver. Set
  `AIRPLAY_HARDWARE_HOST` (and optionally `AIRPLAY_HARDWARE_PORT`) to run it;
  without them every test skips and the lane succeeds. The same lane exercises
  the legacy control plane and photo display against a legacy device; it records
  the model, firmware and outcome.

`rake` runs unit and protocol. `rake test:all` runs all three.

Set `AIRPLAY_LIVE_DISCOVERY=1` to add the opt-in live-network browse check to the
protocol lane; it skips otherwise.

The virtual receiver and the mDNS responder are dev-only: they are absent from
both runtime gemspecs and are never loaded by the library.
