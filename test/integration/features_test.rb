require_relative "../test_helper"
require "minitest/mock"

describe "Airplay feature discovery" do
  it "should get the node feature support" do
    Airplay.stub :nodes, stubbed_nodes do
      airplay_node = Airplay.nodes.first
      features = airplay_node.features

      assert features.video
      assert features.photo
    end
  end
end
