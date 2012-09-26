require_relative "../test_helper"

describe "Airplay client connection" do
  it "should two parallel connections to the airplay server" do
    client = Airplay::Client.new

    with_cassette("creating parallel connections") do
      assert_equal "Apple TV", client.active.name
      assert_equal 2, client.connections.size
    end
  end
end
