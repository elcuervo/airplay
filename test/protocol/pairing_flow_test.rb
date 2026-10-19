require "test_helper"
require "tmpdir"

class PairingFlowTest < Airplay::TestCase
  def test_a_transient_exchange_derives_matching_control_keys
    with_receiver(pairing: {}) do |receiver|
      setup = nil

      Airplay.sync do
        Airplay::Session.open(receiver.device) do |session|
          setup = Airplay::Pairing::Setup.new.run(session)
        end
      end

      assert setup.transient?
      assert_equal 2, receiver.pairing_messages["/pair-setup"].length
      assert_equal setup.control_keys, receiver.control_keys
      assert_equal setup.event_keys, receiver.event_keys
      assert_equal 4, setup.control_keys.length + setup.event_keys.length
    end
  end

  def test_a_transient_exchange_writes_no_credentials
    Dir.mktmpdir do |dir|
      with_env("XDG_CONFIG_HOME" => dir) do
        with_receiver(pairing: {}) do |receiver|
          Airplay.sync do
            Airplay::Session.open(receiver.device) do |session|
              Airplay::Pairing::Setup.new.run(session)
            end
          end
        end

        assert_empty Dir.children(dir)
      end
    end
  end

  def test_a_pin_exchange_stores_a_usable_record
    Dir.mktmpdir do |dir|
      store = Airplay::Pairing::CredentialStore.new(directory: dir)

      with_receiver(pairing: { pin: "1234" }) do |receiver|
        setup = nil

        Airplay.sync do
          Airplay::Session.open(receiver.device) do |session|
            setup = Airplay::Pairing::Setup.new(code: "1234", transient: false, store: store).run(session)
          end
        end

        record = store.read("Fake_Apple_TV")
        refute setup.transient?
        assert_equal setup.identifier, record["identifier"]
        assert_equal record, setup.record
        assert_equal 3, receiver.pairing_messages["/pair-setup"].length
        assert_equal record["client_public"].bytes, receiver.pairings[setup.identifier]
        assert_equal 32, record["client_public"].bytes.bytesize
        assert_equal 32, record["accessory_public"].bytes.bytesize
        assert_equal 0o600, File.stat(store.path_for("Fake_Apple_TV")).mode & 0o777
        assert_equal 0o700, File.stat(dir).mode & 0o777
      end
    end
  end

  def test_a_wrong_pin_writes_nothing
    Dir.mktmpdir do |dir|
      store = Airplay::Pairing::CredentialStore.new(directory: dir)

      with_receiver(pairing: { pin: "1234" }) do |receiver|
        error = assert_raises(Airplay::AuthFailedError) do
          Airplay.sync do
            Airplay::Session.open(receiver.device) do |session|
              Airplay::Pairing::Setup.new(code: "0000", transient: false, store: store).run(session)
            end
          end
        end

        assert_equal :auth_failed, error.code
        assert_empty Dir.children(dir)
        refute receiver.pairing_complete?
      end
    end
  end

  def test_flow_selection_is_table_driven
    Dir.mktmpdir do |dir|
      store = Airplay::Pairing::CredentialStore.new(directory: dir)

      { "4" => [:transient, 2], "3" => [:pin, 3] }.each do |header, (flow, requests)|
        with_receiver(pairing: { pin: "1234" }) do |receiver|
          setup = nil

          options = header == "3" ? { code: "1234", store: store } : {}
          Airplay.sync do
            Airplay::Session.open(receiver.device) do |session|
              setup = Airplay::Pairing::Setup.from_header(header, **options).run(session)
            end
          end

          assert_equal flow, setup.flow
          assert_equal requests, receiver.pairing_messages["/pair-setup"].length
        end
      end

      error = assert_raises(Airplay::TransportError) { Airplay::Pairing::Setup.from_header("9") }
      assert_equal :connect_failed, error.code
    end
  end

  def test_receiver_pairing_errors_map_onto_the_failure_contract
    {
      0x01 => :connect_failed,
      0x02 => :auth_failed,
      0x03 => :auth_failed,
      0x05 => :auth_failed,
      0x06 => :connect_failed,
      0x07 => :connect_failed
    }.each do |value, expected|
      script = { 6 => "\x02".b, 7 => [value].pack("C") }

      with_receiver(pairing: { responses: { "/pair-setup" => [script] } }) do |receiver|
        error = assert_raises(Airplay::Error) do
          Airplay.sync do
            Airplay::Session.open(receiver.device) do |session|
              Airplay::Pairing::Setup.new.run(session)
            end
          end
        end

        assert_equal expected, error.code
        assert_equal 1, receiver.exchanges.length
      end
    end
  end

  def test_a_rejected_pairing_retries_on_a_fresh_connection
    with_receiver(pairing: { faults: { wrong_pin: true, wedge: true } }) do |receiver|
      setup = Airplay.sync { Airplay::Pairing::Setup.pair(receiver.device, attempts: 2) }

      assert setup
      assert_equal 2, receiver.connections
      assert_equal 4, receiver.exchanges.length

      first_connection = receiver.exchanges.first.connection
      assert_equal 2, receiver.exchanges.count { |exchange| exchange.connection.equal?(first_connection) }
      refute receiver.exchanges.last.connection.equal?(first_connection)
      assert receiver.pairing_complete?
    end
  end

  def test_an_always_rejecting_receiver_stops_at_the_attempt_cap
    with_receiver(pairing: { accept: false }) do |receiver|
      error = assert_raises(Airplay::AuthFailedError) do
        Airplay.sync { Airplay::Pairing::Setup.pair(receiver.device, attempts: 2) }
      end

      assert_equal :auth_failed, error.code
      assert_equal 2, receiver.connections
      assert_equal 2, receiver.exchanges.length
    end
  end

  def test_pair_verify_derives_the_channel_keys_after_a_pin_pairing
    Dir.mktmpdir do |dir|
      store = Airplay::Pairing::CredentialStore.new(directory: dir)

      with_receiver(pairing: { pin: "1234" }) do |receiver|
        Airplay.sync do
          setup_connection = Airplay::Pairing::Connection.new(host: "127.0.0.1", port: receiver.port).open
          Airplay::Pairing::Setup.new(code: "1234", transient: false, store: store,
                                      device: "Fake_Apple_TV").run(setup_connection)
          setup_connection.close

          connection = Airplay::Pairing::Connection.new(host: "127.0.0.1", port: receiver.port).open
          verify = Airplay::Pairing::Verify.new(store.read("Fake_Apple_TV")).run(connection)

          assert connection.encrypted?
          assert_equal receiver.control_keys, verify.control_keys
          assert_equal receiver.event_keys, verify.event_keys

          response = connection.request("GET", "/info")
          assert_equal 200, response.status
          assert_equal 1, receiver.framed_requests
          assert_equal "/info", receiver.exchanges.last.path
          connection.close
        end
      end
    end
  end

  private

  def with_env(values)
    previous = values.to_h { |key, _| [key, ENV[key]] }
    values.each { |key, value| ENV[key] = value }
    yield
  ensure
    previous.each { |key, value| value ? ENV[key] = value : ENV.delete(key) }
  end
end
