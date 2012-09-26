require_relative "../test_helper"

describe "Airplay node discovery" do
  it "should find a node in the network" do
    assert Airplay.nodes.size > 0, "At least a node should be found"
    assert Airplay.use("Apple TV")
    assert_equal "Apple TV", Airplay.active.name
  end
end
