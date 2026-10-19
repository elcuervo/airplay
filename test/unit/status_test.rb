require "test_helper"
require "airplay/status"

class StatusTest < Airplay::TestCase
  def test_events_carry_named_fields
    Airplay::Status.emit("playback.progress", position: 4, duration: 10)

    event = last_event
    assert_equal "info", event["severity"]
    assert_equal "playback.progress", event["subject"]
    assert_equal 4, event["position"]
    assert_equal 10, event["duration"]
  end

  def test_default_level_hides_debug_events
    Airplay::Status.emit("session.debug", level: :debug, detail: "hidden")

    assert_empty @output.string
  end

  def test_debug_level_reveals_debug_events
    Airplay.configure do |config|
      config.output = @output = StringIO.new
      config.log_level = :debug
    end

    Airplay::Status.emit("session.debug", level: :debug, detail: "shown")

    assert_equal "shown", last_event["detail"]
  end

  def test_progress_is_only_rendered_for_a_terminal
    assert_nil Airplay::Status.progress("Playback", 10)

    tty = Class.new(StringIO) do
      def tty? = true
    end.new
    Airplay.configure { |config| config.output = tty }

    assert_instance_of Console::Progress, Airplay::Status.progress("Playback", 10)
  end

  private

  def last_event
    JSON.parse(@output.string.lines.last)
  end
end
