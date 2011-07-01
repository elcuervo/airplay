require File.expand_path("helper", File.dirname(__FILE__))

scope do
  setup do
    @airplay = Airplay::Client.new
  end

  test "browse for available airplay servers" do
    assert_equal 1, @airplay.servers.size
  end

  test "find servers by name" do
    airplay = Airplay::Client.new
    assert @airplay.find_by_name("elCuervo").is_a?(Airplay::Node)
  end

  test "raise on not found" do
    assert_raise Airplay::ServerNotFoundError do
      @airplay.find_by_name("NotARealAirplayServer")
    end
  end

  test "autoselect if only one server available" do
    assert_equal "elCuervo", @airplay.active_server.name
  end
end

scope do
  test "send an image to the server" do
    airplay = Airplay::Client.new
    airplay.use("elCuervo")
  end
end
