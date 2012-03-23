require File.expand_path("helper", File.dirname(__FILE__))

scope do

  setup do
    @airplay = Airplay::Client.new(false, MockedBrowser)
  end

  test "browse for available airplay servers" do
    assert @airplay.servers.size > 0
  end

  test "find servers by name" do
    assert @airplay.find_by_name("Mock TV").is_a?(Airplay::Server::Node)
  end

  test "raise on not found" do
    assert_raise Airplay::Client::ServerNotFoundError do
      @airplay.find_by_name("NotARealAirplayServer")
    end
  end

  test "autoselect if only one server available" do
    assert_equal "Mock TV", @airplay.active.name
  end

end
