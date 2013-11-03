require "test_helper"
require "airplay/configuration"

describe Airplay::Configuration do
  Given(:configuration) { Airplay::Configuration.new }

  context "default configuration" do
    Then { configuration.log_level == 4 }
    Then { configuration.autodiscover == true }
    Then { configuration.host == "0.0.0.0" }
    Then { configuration.port == "1337" }
    Then { configuration.output.respond_to?(:info) }
  end

  context "changing configuration" do
    When do
      configuration.log_level = 1
      configuration.autodiscover = false
      configuration.host = "200.47.220.245"
      configuration.port = "80"
    end

    Then { configuration.log_level == 1 }
    And  { configuration.autodiscover == false }
    And  { configuration.host == "200.47.220.245" }
    And  { configuration.port == "80" }
  end
end
