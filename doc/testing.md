# Testing

Tests are split into three lanes:

- `rake test:unit` — configuration, device model, error taxonomy, status events
  and the injectable clock. No sockets, no reactor.
- `rake test:protocol` — the in-process virtual receiver (`airplay-fake-device`)
  driving sessions over loopback: request recording, timeouts, cancellation,
  reactor safety and fault injection. No Apple TV, avahi or ffmpeg required.
- `rake test:hardware` — opt-in validation against a real receiver. Set
  `AIRPLAY_HARDWARE_HOST` (and optionally `AIRPLAY_HARDWARE_PORT`) to run it;
  without them every test skips and the lane succeeds.

`rake` runs unit and protocol. `rake test:all` runs all three.

The virtual receiver is a dev-only package: it is absent from both runtime
gemspecs and is never loaded by the library.
