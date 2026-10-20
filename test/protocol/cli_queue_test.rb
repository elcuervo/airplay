require "test_helper"
require "airplay/cli"
require "tmpdir"

class CLIQueueTest < Airplay::TestCase
  URL = "http://example.com/movie.mp4"
  MODERN = 1 << 49

  def test_play_uses_the_queue_route_on_a_modern_receiver
    with_credentials do
      with_receiver(pairing: { pin: "1234" }, record: { srcvers: "870.14.1" }, queue: {}) do |receiver|
        pair(receiver)
        seed_device(receiver, features: MODERN, srcvers: "870.14.1")

        output, error = capture_io do
          assert Airplay::CLI.run(["play", URL, "--device", "Fake_Apple_TV"])
        end

        assert_empty error
        assert_includes output, "route: queue"
        assert_includes output, "firmware: 870.14.1"
        assert_includes output, "profile: tvos-26.5"
        assert(receiver.commands.any? { |command| command["type"] == "insertPlayQueueItem" })
      end
    end
  end

  def test_play_falls_back_to_legacy_without_modern_video_control
    with_credentials do
      with_receiver(pairing: { pin: "1234" }, queue: {}) do |receiver|
        pair(receiver)
        seed_device(receiver, features: 1 << 0, srcvers: "220.68")

        output, = capture_io do
          assert Airplay::CLI.run(["play", URL, "--device", "Fake_Apple_TV"])
        end

        assert_includes output, "route: legacy"
        assert_includes output, "does not report modern video control"
        assert_empty receiver.commands
      end
    end
  end

  def test_unknown_firmware_uses_the_conservative_legacy_route
    with_credentials do
      with_receiver(pairing: { pin: "1234" }, queue: {}) do |receiver|
        pair(receiver)
        seed_device(receiver, features: MODERN, srcvers: nil)

        output, = capture_io do
          assert Airplay::CLI.run(["play", URL, "--device", "Fake_Apple_TV"])
        end

        assert_includes output, "route: legacy"
        assert_includes output, "conservative policy"
        assert_includes output, "firmware: unknown"
        assert_empty receiver.commands
      end
    end
  end

  def test_transport_verbs_are_dispatched_on_the_queue_route
    with_credentials do
      with_receiver(pairing: { pin: "1234" }, queue: {}) do |receiver|
        pair(receiver)
        seed_device(receiver, features: MODERN, srcvers: "870.14.1")

        %w[pause resume stop next previous].each do |verb|
          capture_io { assert Airplay::CLI.run([verb, "--device", "Fake_Apple_TV"]) }
        end
        capture_io { assert Airplay::CLI.run(["rate", "2.0", "--device", "Fake_Apple_TV"]) }
        capture_io do
          Airplay::CLI.send(:transport, device: "Fake_Apple_TV") do |player|
            player.play(URL)
            player.seek(30.0)
          end
        end

        types = receiver.commands.map { |command| command["type"] }
        assert_includes types, "seekToTime"
        assert_includes types, "setRate"
        refute(receiver.exchanges.any? { |exchange| %w[/rate /scrub].include?(exchange.path) })
      end
    end
  end

  def test_play_wait_drives_the_display_from_receiver_state
    queue = { playback_info: [:playing, :empty] }
    with_credentials do
      with_receiver(pairing: { pin: "1234" }, record: { srcvers: "870.14.1" },
                    queue: queue) do |receiver|
        pair(receiver)
        seed_device(receiver, features: MODERN, srcvers: "870.14.1")

        capture_io do
          assert Airplay::CLI.run(["play", URL, "--device", "Fake_Apple_TV", "--wait"])
        end

        assert_includes @output.string, "playback.state"
        assert_includes @output.string, "playing"
        assert_includes @output.string, "stopped"
      end
    end
  end

  def test_now_playing_can_be_disabled_from_the_cli
    with_credentials do
      with_receiver(pairing: { pin: "1234" }, record: { srcvers: "870.14.1" }, queue: {}) do |receiver|
        pair(receiver)
        seed_device(receiver, features: MODERN, srcvers: "870.14.1")

        capture_io do
          assert Airplay::CLI.run(["play", URL, "--device", "Fake_Apple_TV",
                                   "--no-now-playing"])
        end
        assert_empty receiver.commands.select { |c| c["type"].to_s.start_with?("update") }
      end
    end
  end

  def test_help_and_parser_agree_on_every_option
    output, = capture_io { assert Airplay::CLI.run(["help"]) }
    parser = Airplay::CLI.send(:option_parser, {})

    parser.top.list.each do |option|
      names = option.long + option.short.to_a
      names.each { |name| assert_includes output, name, "option #{name} is undocumented" }
    end
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

  def seed_device(receiver, features:, srcvers:)
    address = Airplay::Discovery::Address.new(ip: "127.0.0.1", family: :ipv4)
    txt = { "features" => format("0x%x", features) }
    txt["srcvers"] = srcvers if srcvers
    record = Airplay::Discovery::ServiceRecord.new(
      name: "Fake_Apple_TV", service_type: "_airplay._tcp", target: "fake.local",
      port: receiver.port, addresses: [address], txt: txt, ttl: 120
    )
    Airplay.instance_variable_set(:@devices, Airplay::Discovery::Devices.new(records: [record]))
  end
end
