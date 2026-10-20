require "test_helper"
require "airplay/cli"
require "json"

class ProtocolDocTest < Airplay::TestCase
  ROOT = File.expand_path("../..", __dir__)
  DOC = File.join(ROOT, "doc/protocol.md")
  USAGE = File.join(ROOT, "doc/usage.md")
  TOC = File.join(ROOT, "doc/toc.md")
  README = File.join(ROOT, "README.md")
  FIXTURES = Dir[File.join(ROOT, "test/fixtures/queue/*.json")]

  def test_the_page_is_wired_into_the_toc_and_the_generated_readme
    assert_includes File.read(TOC), "[Video play queue](#video-play-queue)"
    assert_includes File.read(README), "## Video play queue"
    assert_includes File.read(File.join(ROOT, "Rakefile")), "protocol"
  end

  def test_every_fixture_command_and_field_appears_in_the_page
    doc = File.read(DOC)

    FIXTURES.each do |path|
      fixture = JSON.parse(File.read(path))
      fixture["registration"].each_key do |field|
        assert_includes doc, "`#{field}`", "#{path}: #{field}"
      end
      fixture["headers"].each_key do |header|
        assert_includes doc, header, "#{path}: #{header}"
      end
      fixture["commands"].each do |command|
        assert_includes doc, "`#{command['type']}`", "#{path}: #{command['type']}"
        command["params"].each_key do |field|
          assert_includes doc, "`#{field}`", "#{path}: #{field}"
        end
      end
    end
  end

  def test_the_profile_table_matches_the_fixtures
    doc = File.read(DOC)

    FIXTURES.each do |path|
      fixture = JSON.parse(File.read(path))
      assert_includes doc, "`#{fixture['profile']}`", path
      assert_includes doc, fixture["sender"], path
      assert_includes doc, fixture["stream_header"], path
      assert_includes doc, fixture["firmware"], path unless fixture["firmware"] == "unknown"
    end
  end

  def test_every_documented_error_code_exists_in_the_taxonomy
    doc = File.read(DOC)

    {
      "auth_required" => Airplay::AuthRequiredError.new("x", code: :auth_required),
      "auth_failed" => Airplay::AuthFailedError.new("x", code: :auth_failed),
      "protocol_error" => Airplay::ProtocolError.new("x", code: :protocol_error),
      "connect_failed" => Airplay::TransportError.new("x", code: :connect_failed)
    }.each do |code, error|
      assert_includes doc, code
      assert_equal code.to_sym, error.code
    end
    %w[playback_not_started control_stream unusable_media_address].each do |code|
      assert_includes doc, code
    end
  end

  def test_the_usage_page_documents_every_action_and_option
    usage = File.read(USAGE)
    output, = capture_io { Airplay::CLI.run(["help"]) }

    Airplay::CLI::ACTIONS.each { |action| assert_includes usage, action }
    Airplay::CLI.send(:option_parser, {}).top.list.each do |option|
      option.long.each { |name| assert_includes usage, name }
      assert_includes output, option.long.first
    end
  end
end
