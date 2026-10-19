require "test_helper"
require "airplay/configuration"

class ConfigurationTest < Airplay::TestCase
  def test_defaults
    configuration = Airplay::Configuration.new

    assert_equal :info, configuration.log_level
    assert configuration.autodiscover
    assert_nil configuration.advertised_address
    assert_equal 5.0, configuration.timeout
    assert_equal $stdout, configuration.output
  end

  def test_accepts_valid_changes
    configuration = Airplay::Configuration.new
    configuration.log_level = "debug"
    configuration.autodiscover = false
    configuration.advertised_address = "192.0.2.10"
    configuration.timeout = 2

    assert_equal :debug, configuration.log_level
    refute configuration.autodiscover
    assert_equal "192.0.2.10", configuration.advertised_address
    assert_equal 2.0, configuration.timeout
  end

  def test_rejects_unknown_log_level
    configuration = Airplay::Configuration.new

    error = assert_raises(Airplay::ConfigurationError) { configuration.log_level = :loud }
    assert_match(/unknown log level/, error.message)
  end

  def test_rejects_non_positive_timeout
    configuration = Airplay::Configuration.new

    assert_raises(Airplay::ConfigurationError) { configuration.timeout = 0 }
  end

  def test_configure_returns_configuration_and_resets
    configured = Airplay.configure { |config| config.log_level = :debug }

    assert_same configured, Airplay.configuration
    assert_equal :debug, Airplay.configuration.log_level

    defaults = Airplay.reset_configuration!
    assert_equal :info, defaults.log_level
  end
end
