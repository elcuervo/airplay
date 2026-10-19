require "bundler/setup"
require "json"
require "minitest/autorun"
require "stringio"

require "airplay"
require "airplay/fake_device"

module Airplay
  # Public: Shared test setup; every test starts from default configuration.
  class TestCase < Minitest::Test
    def setup
      Airplay.reset_configuration!
      @output = StringIO.new
      Airplay.configure { |config| config.output = @output }
    end

    def teardown
      Airplay.reset_configuration!
    end

    def with_receiver(**options)
      Airplay.sync do
        receiver = Airplay::FakeDevice::Receiver.new(**options).start
        begin
          yield receiver
        ensure
          receiver.stop
        end
      end
    end
  end
end
