require_relative "../test_helper"

describe "Airplay feature discovery" do
  it "should get the node feature support" do
    node = Airplay.nodes.first
    features = node.features

    assert features.video
    assert features.photo
  end
end
