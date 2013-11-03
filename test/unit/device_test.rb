require "test_helper"
require "airplay/device"

describe Airplay::Device do
  context "a Device must have at least a name and an address" do
    When(:result) { Airplay::Device.new name: "Test" }
    Then { result == Failure(Airplay::Device::MissingAttributes) }

    When(:result) { Airplay::Device.new address: "192.168.1.1:80" }
    Then { result == Failure(Airplay::Device::MissingAttributes) }
  end
end
