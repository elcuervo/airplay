require "test_helper"
require "airplay/errors"

class ErrorsTest < Airplay::TestCase
  CASES = {
    Airplay::Error => :airplay_error,
    Airplay::TransportError => :transport_error,
    Airplay::TimeoutError => :timeout,
    Airplay::ProtocolError => :protocol_error,
    Airplay::AuthenticationError => :authentication_error,
    Airplay::AuthRequiredError => :auth_required,
    Airplay::AuthFailedError => :auth_failed,
    Airplay::PlaybackError => :playback_error,
    Airplay::TimingError => :timing_error,
    Airplay::ConfigurationError => :configuration_error,
    Airplay::SessionClosedError => :session_closed,
    Airplay::UnsupportedError => :unsupported
  }.freeze

  def test_each_error_has_a_stable_code
    CASES.each do |klass, code|
      error = klass.new("boom")

      assert_equal code, error.code, klass.name
      assert_equal "boom", error.message
    end
  end

  def test_instance_can_override_the_code
    error = Airplay::TransportError.new("refused", code: :connection_refused)

    assert_equal :connection_refused, error.code
    assert_equal :transport_error, error.class.code
  end
end
