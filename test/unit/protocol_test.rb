require_relative "../test_helper"
require "net/ptth/test"

describe "Airplay protocol events connection" do
  before do
    request = Net::HTTP::Post.new("/event")
    request.body = <<-EOS.gsub(/^\s+/, '')
      <?xml version="1.0" encoding="UTF-8"?>
      <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
      <plist version="1.0">
       <dict>
        <key>category</key>
        <string>video</string>
        <key>state</key>
        <string>loading</string>
       </dict>
      </plist>
    EOS

    @server = Net::PTTH::TestServer.new(port: 12345, response: request)
    Thread.new { @server.start }
  end

  after do
    @server.close
  end

  it "should get events from the server" do
    Airplay.stub :nodes, stubbed_nodes do
      Airplay.stub :active, stubbed_nodes.first do
        reverse = Airplay::Protocol::Reverse.new(Airplay.active)
        reverse.callbacks << proc do |response|
          assert_equal "video",   response["category"]
          assert_equal "loading", response["state"]

          reverse.disconnect
        end

        reverse.connect
      end
    end

  end
end
