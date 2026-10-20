require "test_helper"
require "airplay/cli"
require "tmpdir"

class QueueErrorTest < Airplay::TestCase
  MODERN = 1 << 49
  URL = "http://example.com/movie.mp4"

  def test_every_contract_code_is_emitted_on_the_status_line
    {
      auth_required: Airplay::AuthRequiredError.new("x", code: :auth_required),
      auth_failed: Airplay::AuthFailedError.new("x", code: :auth_failed),
      playback_not_started: Airplay::PlaybackError.new("x", code: :playback_not_started),
      control_stream: Airplay::ProtocolError.new("x", code: :control_stream),
      connect_failed: Airplay::TransportError.new("x", code: :connect_failed)
    }.each do |code, error|
      error.emit!
      assert_includes @output.string, code.to_s
    end
  end

  def test_an_error_is_emitted_once
    error = Airplay::ProtocolError.new("x", code: :control_stream)

    2.times { error.emit! }

    assert_equal 1, @output.string.scan("control_stream").length
  end

  def test_the_library_path_emits_a_refused_control_stream
    with_credentials do
      with_receiver(pairing: { pin: "1234" }, record: { name: "Fake_Apple_TV", srcvers: "870.14.1" },
                    queue: { refuse_stream: true, stream_status: 403 }) do |receiver|
        pair(receiver)
        capabilities = Airplay::Discovery::Capabilities.new(
          "features" => format("0x%x", MODERN), "srcvers" => "870.14.1"
        )

        error = assert_raises(Airplay::ProtocolError) do
          Airplay::Player.open(receiver.device, capabilities: capabilities) do |player|
            player.play(URL)
          end
        end

        assert_equal :control_stream, error.code
        assert_includes @output.string, "control_stream"
      end
    end
  end

  def test_the_cli_path_emits_a_connection_failure
    _, error_output = capture_io do
      refute Airplay::CLI.run(["play", URL, "--url", "http://127.0.0.1:1"])
    end

    assert_includes error_output, "connection_refused"
    assert_includes @output.string, "connection_refused"
  end

  private

  def with_credentials
    Dir.mktmpdir do |dir|
      ENV["AIRPLAY_CREDENTIALS_DIR"] = dir
      yield
    ensure
      ENV.delete("AIRPLAY_CREDENTIALS_DIR")
    end
  end

  def pair(receiver)
    store = Airplay::Pairing::CredentialStore.new(directory: ENV.fetch("AIRPLAY_CREDENTIALS_DIR"))
    connection = verified_connection(store, receiver)
    connection.close
  end
end
