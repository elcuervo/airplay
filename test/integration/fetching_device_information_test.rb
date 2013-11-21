require "integration_helper"

describe "Getting information from a device" do
  Given(:device) { test_device }

  context "getting the id" do
    When(:id) { device.id }
    Then { id == "58:55:CA:1F:3E:80" }
  end

  context "getting some minimun info" do
    When(:min_info) { device.info }
    Then { min_info.model == "AppleTV2,1" }
    And  { min_info.respond_to?(:os_version) }
    And  { min_info.respond_to?(:mac_address) }
  end

  context "getting server information" do
    When(:full_info) { device.server_info }
    Then { full_info.keys.size == 17 }
  end
end
