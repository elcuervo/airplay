require "test_helper"
require "airplay/device"

test "a Device must have at least a name and an address" do
  assert_raise Airplay::Device::MissingAttributes do
    Airplay::Device.new name: "Test"
  end

  assert_raise Airplay::Device::MissingAttributes do
    Airplay::Device.new address: "192.168.1.1:80"
  end
end
