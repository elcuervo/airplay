require "test_helper"
require "airplay/cli"
require "digest"
require "tmpdir"

class CLIVerbsTest < Airplay::TestCase
  def test_play_targets_an_explicit_receiver
    with_receiver(legacy: { script: { ["POST", "/play"] => { status: 200 } } }) do |receiver|
      output, error = capture_io do
        assert Airplay::CLI.run(["play", "http://example.com/movie.mp4", "--url", receiver.url])
      end

      assert_empty error
      assert_includes output, "route: legacy"
      assert_includes receiver.exchanges.last.body, "Content-Location: http://example.com/movie.mp4"
    end
  end

  def test_view_sends_the_documented_transition
    Dir.mktmpdir do |dir|
      image = File.join(dir, "photo.png")
      File.binwrite(image, "\x89PNG\r\n\x1A\n\xFF".b)

      with_receiver(legacy: { script: { ["PUT", "/photo"] => { status: 200 } } }) do |receiver|
        capture_io do
          assert Airplay::CLI.run(["view", image, "--url", receiver.url, "--transition", "Dissolve"])
        end

        assert_equal "Dissolve", receiver.photo_transition
        assert_equal Digest::SHA256.hexdigest(File.binread(image)), receiver.photo_digest
      end
    end
  end

  def test_view_runs_a_folder_slideshow
    Dir.mktmpdir do |dir|
      %w[a.png b.png].each { |name| File.binwrite(File.join(dir, name), name) }

      with_receiver(legacy: { script: { ["PUT", "/photo"] => { status: 200 } } }) do |receiver|
        capture_io do
          assert Airplay::CLI.run(["view", dir, "--url", receiver.url, "--wait", "0"])
        end

        assert_equal 2, receiver.exchanges.count { |exchange| exchange.path == "/photo" }
      end
    end
  end

  def test_authentication_failure_exits_non_zero_with_the_code
    digest = { realm: "AirPlay", nonce: "n", qop: true, username: "Airplay", password: "right" }

    with_receiver(legacy: { script: { ["POST", "/play"] => { status: 200 } }, digest: digest }) do |receiver|
      _, error = capture_io do
        refute Airplay::CLI.run(["play", "http://example.com/x", "--url", receiver.url,
                                 "--password", "wrong"])
      end

      assert_includes error, "auth_failed"
      refute_includes error, "wrong"
    end
  end

  def test_play_can_wait_for_completion
    script = {
      ["POST", "/play"] => { status: 200 },
      ["GET", "/playback-info"] => {
        body: Airplay::Plist.dump("rate" => 0, "duration" => 10, "position" => 10)
      }
    }

    with_receiver(legacy: { script: script }) do |receiver|
      capture_io do
        assert Airplay::CLI.run(["play", "http://example.com/x", "--url", receiver.url, "--wait"])
      end

      assert_equal 1, receiver.exchanges.count { |exchange| exchange.path == "/playback-info" }
    end
  end
end
