require "integration_helper"

scope "Browsing the network for available Apple TVs" do
  setup do
    @browser = Airplay::Browser.new
    @browser.browse

    sleep 5 # Wait for devices
  end

  test "should be at least one device" do
    assert @browser.devices.count > 0
  end
end
