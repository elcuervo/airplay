require "bundler/setup"
require "json"
require "minitest/autorun"
require "stringio"

require "airplay"
require "airplay/fake_device"
require "support/range_client"

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

    # Public: Completes a PIN pairing and pair-verify, returning the framed connection.
    def establish_pairing(store, receiver, pin: "1234")
      setup = Airplay::Pairing::Connection.new(host: "127.0.0.1", port: receiver.port).open
      Airplay::Pairing::Setup.new(code: pin, transient: false, store: store,
                                  device: "Fake_Apple_TV").run(setup)
      setup.close

      connection = Airplay::Pairing::Connection.new(host: "127.0.0.1", port: receiver.port).open
      Airplay::Pairing::Verify.new(store.read("Fake_Apple_TV")).run(connection)
      connection
    end
  end
end
