require "test_helper"
require "airplay/device"

class DeviceTest < Airplay::TestCase
  def test_requires_a_name_and_an_address
    assert_raises(Airplay::Device::MissingAttributes) do
      Airplay::Device.new(name: "Test")
    end

    assert_raises(Airplay::Device::MissingAttributes) do
      Airplay::Device.new(address: "192.0.2.10:7000")
    end
  end

  def test_parses_an_address
    device = Airplay::Device.new(name: "TV", address: "192.0.2.10:7000")

    assert_equal "192.0.2.10", device.host
    assert_equal 7000, device.port
    assert_equal "192.0.2.10:7000", device.address
  end

  def test_defaults_the_port
    device = Airplay::Device.new(name: "TV", host: "192.0.2.10")

    assert_equal 7000, device.port
  end

  def test_password_presence_and_replacement
    device = Airplay::Device.new(name: "TV", host: "192.0.2.10")

    refute device.password?
    replacement = device.with_password("hunter2")
    assert replacement.password?
    refute_same device, replacement
  end
end
