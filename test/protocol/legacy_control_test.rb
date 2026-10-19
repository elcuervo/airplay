require "test_helper"

class LegacyControlTest < Airplay::TestCase
  SERVER_INFO = { "deviceid" => "AA:BB", "model" => "AppleTV3,2", "srcvers" => "220.68",
                  "features" => "0x5A7FFFF7,0x1E" }.freeze

  def test_a_scripted_play_is_recorded_verbatim
    with_legacy(script: { ["POST", "/play"] => { status: 200 } }) do |receiver, session|
      assert session.play("http://example.com/movie.mp4", position: 0.5)

      exchange = receiver.exchanges.last
      assert_equal "POST", exchange.method
      assert_equal "/play", exchange.path
      assert_equal "text/parameters", exchange.headers["content-type"]
      assert_equal "Content-Location: http://example.com/movie.mp4\r\nStart-Position: 0.5\r\n",
                   exchange.body
    end
  end

  def test_session_identity_headers_are_stable_and_distinct
    with_legacy(script: { ["GET", "/server-info"] => { body: Airplay::Plist.dump_xml(SERVER_INFO) } }) do |receiver, session|
      session.server_info
      session.server_info
      session.server_info
      identifiers = receiver.exchanges.map { |exchange| exchange.headers["x-apple-session-id"] }
      assert_equal 1, identifiers.uniq.length
      assert_equal 3, identifiers.length
      assert_equal 1, receiver.connections
      device_ids = receiver.exchanges.map { |exchange| exchange.headers["x-apple-device-id"] }
      assert_equal 1, device_ids.uniq.length
      assert_match(/\A0x[0-9a-f]{12}\z/, device_ids.first)
      assert_equal "MediaControl/1.0", receiver.exchanges.first.headers["user-agent"]
      @session_id = identifiers.first

    end

    with_legacy(script: {}) do |receiver, session|
      session.get("/x")
      other = receiver.exchanges.first.headers["x-apple-session-id"]
      refute_equal @session_id, other
    end
  end

  def test_server_info_preserves_every_key_and_fails_cleanly
    with_legacy(script: { ["GET", "/server-info"] => { body: Airplay::Plist.dump_xml(SERVER_INFO) } }) do |_receiver, session|
      info = session.server_info

      assert_equal "AppleTV3,2", info["model"]
      assert_equal "220.68", info["srcvers"]
      assert_equal "0x5A7FFFF7,0x1E", info["features"]
    end

    with_legacy(script: { ["GET", "/server-info"] => { status: 500, body: "error" } }) do |receiver, session|
      error = assert_raises(Airplay::ProtocolError) { session.server_info }

      assert_equal 500, error.status
      assert_equal 1, receiver.exchanges.count { |exchange| exchange.path == "/server-info" }
    end

    with_legacy(script: { ["GET", "/server-info"] => { body: "<html>nope</html>" } }) do |_receiver, session|
      assert_raises(Airplay::ProtocolError) { session.server_info }
    end
  end

  def test_playing_without_an_argument_uses_the_queued_item
    with_legacy(script: { ["POST", "/play"] => { status: 200 } }) do |receiver, session|
      session.playlist << Airplay::Media::Media.new(url: "http://example.com/queued.mp4")
      session.play

      assert_includes receiver.exchanges.last.body, "Content-Location: http://example.com/queued.mp4"
    end
  end

  def test_transport_commands_and_refusals
    script = {
      ["POST", "/rate?value=0"] => { status: 200 },
      ["POST", "/rate?value=1"] => { status: 200 },
      ["POST", "/rate?value=2"] => { status: 200 },
      ["POST", "/stop"] => { status: 200 },
      ["POST", "/scrub?position=20.097"] => { status: 200 }
    }

    with_legacy(script: script) do |receiver, session|
      session.rate(0)
      session.rate(1)
      session.rate(2)
      session.stop
      session.scrub(20.097)

      assert_equal ["/rate?value=0", "/rate?value=1", "/rate?value=2", "/stop",
                    "/scrub?position=20.097"], receiver.exchanges.map(&:path)
    end

    with_legacy(script: {}) do |receiver, session|
      assert_raises(Airplay::PlaybackError) { session.scrub(-1) }
      assert_raises(Airplay::PlaybackError) { session.play("http://x/y", position: 1.5) }
      assert_empty receiver.exchanges
    end
  end

  def test_stopping_an_idle_session_still_issues_the_request
    with_legacy(script: { ["POST", "/stop"] => { status: 200 } }) do |receiver, session|
      session.stop
      assert_equal ["/stop"], receiver.exchanges.map(&:path)
    end
  end

  def test_error_statuses_and_truncated_bodies_surface_typed_errors
    { 400 => Airplay::PlaybackError, 404 => Airplay::PlaybackError, 500 => Airplay::PlaybackError }
      .each do |status, error_class|
      with_legacy(script: { ["POST", "/play"] => { status: status } }) do |_receiver, session|
        error = assert_raises(error_class) { session.play("http://example.com/x") }
        assert_equal status, error.status
      end
    end

    with_legacy(script: { ["GET", "/scrub"] => { status: 404 } }) do |_receiver, session|
      error = assert_raises(Airplay::ProtocolError) { session.scrub }
      assert_equal 404, error.status
    end

    with_legacy(script: { ["GET", "/server-info"] => { status: 200, body: "not a plist" } }) do |_receiver, session|
      assert_raises(Airplay::ProtocolError) { session.server_info }
    end
  end

  def test_set_property_body_and_error_code
    answer = Airplay::Plist.dump("errorCode" => 0)
    value = { "epoch" => 0, "flags" => 0, "timescale" => 1000, "value" => 5000 }

    with_legacy(script: { ["PUT", "/setProperty?forwardEndTime"] => { status: 200, body: answer } }) do |receiver, session|
      assert_equal 0, session.set_property("forwardEndTime", value)["errorCode"]

      exchange = receiver.exchanges.last
      assert_equal "PUT", exchange.method
      assert_equal "/setProperty?forwardEndTime", exchange.path
      assert_equal "application/x-apple-binary-plist", exchange.headers["content-type"]
      assert_equal value, exchange.plist
    end

    failing = Airplay::Plist.dump("errorCode" => 7)
    with_legacy(script: { ["PUT", "/setProperty?forwardEndTime"] => { status: 200, body: failing } }) do |_receiver, session|
      error = assert_raises(Airplay::PlaybackError) { session.set_property("forwardEndTime", value) }
      assert_equal 7, error.code
    end
  end

  def test_digest_challenge_and_qop_replay
    digest = { realm: "AirPlay", nonce: "abc123", qop: true, username: "Airplay", password: "hunter2" }
    script = { ["GET", "/server-info"] => { body: Airplay::Plist.dump_xml(SERVER_INFO) } }

    with_legacy(script: script, digest: digest) do |receiver, session|
      device = receiver.device(password: "hunter2")
      session = Airplay::Session.new(device)
      session.server_info

      assert_equal 2, receiver.exchanges.count { |exchange| exchange.path == "/server-info" }
      authorization = receiver.exchanges.last.headers["authorization"]
      assert_includes authorization, 'username="Airplay"'
      assert_includes authorization, 'realm="AirPlay"'
      assert_includes authorization, "qop=auth"
      assert_includes authorization, "nc=00000001"
      assert_includes authorization, "cnonce="
      session.close
    end
  end

  def test_digest_raop_realm_selects_itunes_and_override_wins
    script = { ["GET", "/server-info"] => { body: Airplay::Plist.dump_xml(SERVER_INFO) } }

    raop = { realm: "raop", nonce: "n", qop: false, username: "iTunes", password: "pw" }
    with_legacy(script: script, digest: raop) do |receiver, _session|
      session = Airplay::Session.new(receiver.device(password: "pw"))
      session.server_info
      assert_includes receiver.exchanges.last.headers["authorization"], 'username="iTunes"'
      session.close
    end

    override = { realm: "raop", nonce: "n", qop: true, username: "Custom", password: "pw" }
    with_legacy(script: script, digest: override) do |receiver, _session|
      session = Airplay::Session.new(receiver.device(password: "pw"), digest_username: "Custom")
      session.server_info
      assert_includes receiver.exchanges.last.headers["authorization"], 'username="Custom"'
      session.close
    end
  end

  def test_auth_required_and_auth_failed_request_counts
    digest = { realm: "AirPlay", nonce: "n", qop: true, username: "Airplay", password: "right" }
    script = { ["GET", "/server-info"] => { body: Airplay::Plist.dump_xml(SERVER_INFO) } }

    with_legacy(script: script, digest: digest) do |receiver, _session|
      session = Airplay::Session.new(receiver.device)
      error = assert_raises(Airplay::AuthRequiredError) { session.server_info }
      assert_equal 401, error.status
      assert_equal 1, receiver.exchanges.length
      assert_equal 1, receiver.digest_missing
      assert_equal 0, receiver.digest_wrong
      session.close
    end

    with_legacy(script: script, digest: digest) do |receiver, _session|
      session = Airplay::Session.new(receiver.device(password: "wrong"))
      error = assert_raises(Airplay::AuthFailedError) { session.server_info }
      assert_equal 401, error.status
      assert_equal 2, receiver.exchanges.length
      assert_equal 1, receiver.digest_missing
      assert_equal 1, receiver.digest_wrong
      session.close
    end
  end

  def test_authentication_failures_never_log_the_secret
    digest = { realm: "AirPlay", nonce: "n", qop: true, username: "Airplay", password: "right" }
    script = { ["GET", "/server-info"] => { body: Airplay::Plist.dump_xml(SERVER_INFO) } }

    with_legacy(script: script, digest: digest) do |receiver, _session|
      session = Airplay::Session.new(receiver.device(password: "hunter2"))
      assert_raises(Airplay::AuthFailedError) { session.server_info }
      session.close

      log = @output.string
      refute_includes log, "hunter2"
      refute_includes log, "response="
      refute_includes log, "Authorization"
    end
  end

  def test_reconnect_replays_reads_but_not_playback
    script = {
      ["GET", "/playback-info"] => { body: Airplay::Plist.dump("rate" => 1) },
      ["POST", "/play"] => { status: 200, truncate: true }
    }

    with_legacy(script: script, close_after_response: true) do |receiver, session|
      assert session.playback_info
      assert session.playback_info
      assert_equal 2, receiver.exchanges.count { |exchange| exchange.path == "/playback-info" }
      assert_equal 2, receiver.connections
      session.close
    end

    with_legacy(script: script, close_after_response: true, truncate: true) do |receiver, session|
      session.playback_info
      error = assert_raises(Airplay::TransportError) { session.play("http://example.com/x") }
      assert_equal :connection_lost, error.code
      assert_equal 1, receiver.exchanges.count { |exchange| exchange.path == "/play" }
      session.close
    end
  end

  def test_explicit_origin_joins_base_paths
    with_legacy(script: { ["GET", "/prefix/server-info"] => { body: Airplay::Plist.dump_xml(SERVER_INFO) } }) do |receiver, _session|
      device = Airplay::Device.new(name: "Direct", host: "192.0.2.10", port: 7000)
      session = Airplay::Session.new(device, base_url: receiver.url + "/prefix/")
      session.server_info
      assert_equal "/prefix/server-info", receiver.exchanges.last.path
      session.close
    end
  end

  def test_an_airplay2_device_is_refused_without_an_override
    capabilities = Airplay::Discovery::Capabilities.new("features" => "0x0,0x40")

    with_legacy(script: { ["GET", "/server-info"] => { body: Airplay::Plist.dump_xml(SERVER_INFO) } }) do |receiver, _session|
      assert_raises(Airplay::UnsupportedError) do
        Airplay::Session.new(receiver.device, capabilities: capabilities)
      end
      assert_empty receiver.exchanges

      session = Airplay::Session.new(receiver.device, capabilities: capabilities, legacy: true)
      session.server_info
      assert_equal 1, receiver.exchanges.length
      session.close
    end
  end

  def test_a_password_hint_is_a_warning_not_a_gate
    capabilities = Airplay::Discovery::Capabilities.new("pw" => "true")
    script = { ["GET", "/server-info"] => { body: Airplay::Plist.dump_xml(SERVER_INFO) } }

    with_legacy(script: script) do |receiver, _session|
      session = Airplay::Session.new(receiver.device, capabilities: capabilities)
      session.server_info

      assert_equal 1, receiver.exchanges.length
      assert_includes @output.string, "password_hint"
      session.close
    end
  end

  def test_a_legacy_failure_never_falls_back_to_the_modern_route
    with_legacy(script: { ["POST", "/play"] => { status: 500 } }) do |receiver, session|
      error = assert_raises(Airplay::PlaybackError) { session.play("http://example.com/x") }

      assert_equal 500, error.status
      assert_equal ["/play"], receiver.exchanges.map(&:path)
    end
  end

  private

  def with_legacy(script: {}, digest: nil, **options)
    with_receiver(legacy: { script: script, digest: digest, **options }) do |receiver|
      session = Airplay::Session.new(receiver.device)
      begin
        yield receiver, session
      ensure
        session.close
      end
    end
  end
end
