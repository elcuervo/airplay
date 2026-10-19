require "test_helper"
require "digest"
require "stringio"
require "tmpdir"

class LegacyPlaybackTest < Airplay::TestCase
  def test_photo_input_kinds_resolve_to_identical_bytes
    image = "\x89PNG\r\n\x1A\n\x00\xFFdata".b

    Dir.mktmpdir do |dir|
      path = File.join(dir, "photo.png")
      File.binwrite(path, image)

      Airplay.sync do
        media = Airplay::Media::Server.new(host: "127.0.0.1")
        url = media.publish(path)

        with_legacy(script: { ["PUT", "/photo"] => { status: 200 } }) do |receiver, session|
          session.photo(path, transition: "Dissolve")
          assert_equal Digest::SHA256.hexdigest(image), receiver.photo_digest
          assert_equal "Dissolve", receiver.photo_transition

          session.photo(StringIO.new(image))
          assert_equal Digest::SHA256.hexdigest(image), receiver.photo_digest

          session.photo(url)
          assert_equal Digest::SHA256.hexdigest(image), receiver.photo_digest

          session.photo(image)
          assert_equal Digest::SHA256.hexdigest(image), receiver.photo_digest
        end

        media.stop
      end
    end
  end

  def test_photo_transitions_and_payload_integrity
    payload = ("line\r\n\xFF" * 5000).b

    with_legacy(script: { ["PUT", "/photo"] => { status: 200 } }) do |receiver, session|
      session.photo(payload, transition: "SlideLeft")
      assert_equal Digest::SHA256.hexdigest(payload), receiver.photo_digest
      assert_equal payload.bytesize, receiver.photo_bytes.bytesize
      assert_equal "SlideLeft", receiver.photo_transition

      session.photo(payload)
      assert_equal "None", receiver.photo_transition
    end
  end

  def test_unknown_transition_and_unsupported_inputs_issue_no_request
    with_legacy(script: { ["PUT", "/photo"] => { status: 200 } }) do |receiver, session|
      assert_raises(Airplay::PlaybackError) { session.photo("bytes", transition: "Cube") }
      assert_raises(Airplay::PlaybackError) { session.photo(42) }
      assert_empty receiver.exchanges
    end
  end

  def test_an_unreachable_photo_url_fails_before_the_request
    with_legacy(script: {}) do |receiver, session|
      assert_raises(Airplay::TransportError) { session.photo("http://127.0.0.1:1/nope.png") }
      assert_empty receiver.exchanges
    end
  end

  def test_playback_information_semantics
    full = Airplay::Plist.dump(
      "duration" => 83.124794, "position" => 14.467, "rate" => 1,
      "readyToPlay" => true, "seekableTimeRanges" => [{ "start" => 0, "duration" => 83.124794 }]
    )

    with_legacy(script: { ["GET", "/playback-info"] => { body: full } }) do |_receiver, session|
      snapshot = session.playback_info

      assert_in_delta 83.124794, snapshot.duration, 0.0001
      assert_in_delta 14.467, snapshot.position, 0.0001
      assert_equal 1, snapshot.rate
      assert snapshot.ready_to_play
      assert_equal [[0.0, 83.124794]], snapshot.seekable
    end

    with_legacy(script: { ["GET", "/playback-info"] => { body: Airplay::Plist.dump("rate" => 1) } }) do |_receiver, session|
      snapshot = session.playback_info
      assert snapshot.playing?
      assert_nil snapshot.duration
    end

    with_legacy(script: { ["GET", "/playback-info"] => { body: Airplay::Plist.dump({}) } }) do |_receiver, session|
      assert session.playback_info.stopped?
    end

    with_legacy(script: { ["GET", "/playback-info"] => { body: "not a plist" } }) do |_receiver, session|
      assert_raises(Airplay::ProtocolError) { session.playback_info }
    end
  end

  def test_scrub_read_parses_seconds_and_rejects_malformed_bodies
    body = "duration: 83.124794\r\nposition: 14.467000\r\n"

    with_legacy(script: { ["GET", "/scrub"] => { body: body } }) do |_receiver, session|
      values = session.scrub
      assert_in_delta 83.124794, values["duration"], 0.0001
      assert_in_delta 14.467, values["position"], 0.0001
    end

    with_legacy(script: { ["GET", "/scrub"] => { body: "garbage" } }) do |_receiver, session|
      assert_raises(Airplay::ProtocolError) { session.scrub }
    end
  end

  def test_one_playback_info_request_per_interval_and_three_subscriptions
    clock = Airplay::FakeDevice::FakeClock.new
    Airplay.clock = clock
    counter = 0
    script = {
      ["GET", "/playback-info"] => lambda do |_request|
        counter += 1
        body = case counter
               when 1 then Airplay::Plist.dump("rate" => 1)
               when 2 then Airplay::Plist.dump("rate" => 1, "duration" => 10, "position" => 5)
               else Airplay::Plist.dump("rate" => 0, "duration" => 10, "position" => 10)
               end
        { status: 200, body: body }
      end
    }

    with_legacy(script: script) do |receiver, session|
      subscriptions = 3.times.map { session.progress(interval: 1) }

      session.poll(interval: 1)
      clock.advance(1)
      session.poll(interval: 1)
      clock.advance(1)
      session.poll(interval: 1)

      assert_equal [3, 3, 3], subscriptions.map(&:size)
      assert_equal 3, receiver.exchanges.count { |exchange| exchange.path == "/playback-info" }
    end
  end

  def test_wait_resolves_on_completion_without_wall_clock
    clock = Airplay::FakeDevice::FakeClock.new
    Airplay.clock = clock
    counter = 0
    script = {
      ["GET", "/playback-info"] => lambda do |_request|
        counter += 1
        body = if counter == 1
                 Airplay::Plist.dump("rate" => 1, "duration" => 10, "position" => 1)
               else
                 Airplay::Plist.dump("rate" => 0, "duration" => 10, "position" => 10)
               end
        { status: 200, body: body }
      end
    }

    with_legacy(script: script) do |receiver, session|
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      assert session.wait(interval: 1)
      elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started

      assert_operator elapsed, :<, 1
      assert_equal :played, session.state.current
      assert_equal 2, receiver.exchanges.count { |exchange| exchange.path == "/playback-info" }
    end
  end

  private

  def with_legacy(script: {}, **options)
    with_receiver(legacy: { script: script, **options }) do |receiver|
      session = Airplay::Session.new(receiver.device)
      begin
        yield receiver, session
      ensure
        session.close
      end
    end
  end
end
