$:.unshift File.dirname(__FILE__) + '/../lib'

require "bundler/setup"
require "minitest/spec"
require "minitest/pride"
require "minitest/autorun"
require "vcr"
require "airplay"

VCR.configure do |c|
  c.cassette_library_dir = 'test/fixtures/cassettes/airplay'
  c.default_cassette_options = { record: :new_episodes }
  c.hook_into :fakeweb
end

def with_cassette(name, &block)
  VCR.use_cassette(name, preserve_exact_body_bytes: true, &block)
end

def stubbed_nodes
  nodes = Airplay::Nodes.new
  node = Airplay::Node.create(
    name: "MockTV",
    address: "127.0.0.1:12345",
    domain: "MockTV.local"
  )

  text_record = {
    "rhd"       =>  "4.6.3",
    "features"  =>  "0x180029FF",
    "deviceid"  =>  "7D:C3:A1:89:88:0C",
    "model"     =>  "AppleTV3,1",
    "vv"        =>  "1",
    "srcvers"   =>  "150.35"
  }

  node.parse_info(text_record)
  nodes << node
end
