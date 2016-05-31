require "integration_helper"

scope "Getting information from a @device" do
  setup do
    @device = test_device
  end

  test "getting the id" do
    assert @device.id == "6C:40:08:AE:BB:F5"
  end

  test "getting some minimun info" do
    min_info = @device.info

    assert min_info.model == "AppleTV5,3"
    assert min_info.respond_to?(:os_version)
    assert min_info.respond_to?(:mac_address)
  end

  test "getting server information" do
    assert @device.server_info.keys.size >= 14
  end
end
