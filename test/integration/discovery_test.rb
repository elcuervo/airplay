require_relative "../test_helper"
require "minitest/mock"

describe "Airplay node discovery" do
  it "should find a node in the network" do
    Airplay.stub :nodes, stubbed_nodes do
      assert Airplay.nodes.size > 0, "At least a node should be found"
      Airplay.stub :active, stubbed_nodes.first do
        assert_equal "MockTV", Airplay.active.name
      end
    end
  end
end
