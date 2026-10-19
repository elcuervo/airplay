require "test_helper"
require "airplay/cli"

class CLITest < Airplay::TestCase
  def test_help_and_version
    output, = capture_io { assert Airplay::CLI.run(["help"]) }
    assert_match(/list/, output)

    output, = capture_io { assert Airplay::CLI.run(["version"]) }
    assert_match(/air \d+\.\d+\.\d+/, output)
  end

  def test_help_documents_the_legacy_route_and_verbs
    output, = capture_io { assert Airplay::CLI.run(["help"]) }

    assert_includes output, "--legacy"
    assert_includes output, "play"
    assert_includes output, "view"
    assert_includes output, "--url"
    assert_includes output, "--transition"
  end

  def test_arrow_keys_map_to_transitions
    assert_equal "SlideLeft", Airplay::CLI.transition_for("\e[C")
    assert_equal "SlideRight", Airplay::CLI.transition_for("\e[D")
    assert_equal "None", Airplay::CLI.transition_for(" ")
    assert_nil Airplay::CLI.transition_for("x")
  end

  def test_unknown_action_fails
    _, error = capture_io do
      refute Airplay::CLI.run(["nope"])
    end

    assert_match(/unknown action/, error)
  end

  def test_list_on_an_empty_network_prints_nothing
    Airplay.configure do |config|
      config.discovery_port = 55_398
      config.discovery_interfaces = ["lo0"]
      config.discovery_window = 0.1
    end

    output, = capture_io { Airplay.sync { assert Airplay::CLI.run(["list"]) } }
    assert_empty output
  end

  def test_doctor_on_an_empty_network_prints_the_empty_outcome
    Airplay.configure do |config|
      config.discovery_port = 55_396
      config.discovery_interfaces = ["lo0"]
      config.discovery_window = 0.1
    end

    output, = capture_io { Airplay.sync { assert Airplay::CLI.run(["doctor"]) } }
    assert_match(/No devices found/, output)
  end

  def test_doctor_reports_a_transport_failure
    Airplay.configure do |config|
      config.discovery_interfaces = ["nope0"]
      config.discovery_window = 0.1
    end

    _, error = capture_io do
      refute Airplay::CLI.run(["doctor"])
    end

    assert_match(/interface_unavailable/, error)
  end
end
