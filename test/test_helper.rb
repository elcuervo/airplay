require "bundler/setup"
require "json"
require "minitest/autorun"
require "stringio"
require "tmpdir"

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

    # Public: Opens a verified encrypted connection to a pairing receiver.
    def verified_connection(store, receiver, pin: "1234")
      setup = Airplay::Pairing::Connection.new(host: "127.0.0.1", port: receiver.port).open
      Airplay::Pairing::Setup.new(code: pin, transient: false, store: store,
                                  device: "Fake_Apple_TV").run(setup)
      setup.close

      connection = Airplay::Pairing::Connection.new(host: "127.0.0.1", port: receiver.port).open
      @verify = Airplay::Pairing::Verify.new(store.read("Fake_Apple_TV")).run(connection)
      connection
    end

    # Public: An established control session against a play-queue receiver.
    def with_queue_session(queue: {}, record: {}, pairing: {}, timeout: 2, &block)
      record = { srcvers: "870.14.1" }.merge(record)
      pairing = { pin: "1234" }.merge(pairing)

      with_receiver(pairing: pairing, record: record, queue: queue) do |receiver|
        Dir.mktmpdir do |dir|
          store = Airplay::Pairing::CredentialStore.new(directory: dir)
          connection = verified_connection(store, receiver)
          session = Airplay::Control::Session.new(connection, timing_port: 7001,
                                                              event_key: @verify.event_keys.first)
          begin
            session.establish
            yield receiver, session
          ensure
            session.close
          end
        end
      end
    end

    def wait_until(timeout: 2, message: "timed out")
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
      until yield
        raise message if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline

        sleep 0.01
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
