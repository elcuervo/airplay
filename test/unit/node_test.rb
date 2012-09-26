require_relative "../test_helper"

describe "Airplay::Node" do
  it "should represent an Airplay node" do
    node = Airplay::Node.create(
      name:    "MockTV",
      address: "127.0.0.1:7000",
      domain:  "local"
    )

    assert_equal "MockTV", node.name
    assert_equal "127.0.0.1:7000", node.address
    assert_equal "local", node.domain
    assert_equal "127.0.0.1", node.ip
    assert_equal 7000, node.port
  end
end
