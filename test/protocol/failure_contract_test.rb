require "test_helper"
require "socket"
require "tmpdir"

class FailureContractTest < Airplay::TestCase
  def test_an_unpaired_device_pairs_without_an_auth_failure
    Dir.mktmpdir do |dir|
      store = Airplay::Pairing::CredentialStore.new(directory: dir)

      with_receiver(pairing: { pin: "1234" }) do |receiver|
        assert store.unpaired?("Fake_Apple_TV")

        setup = Airplay.sync { Airplay::Pairing::Setup.pair(receiver.device, code: "1234", transient: false, store: store) }
        refute store.unpaired?("Fake_Apple_TV")
        assert_equal 3, receiver.pairing_messages["/pair-setup"].length
        assert_equal store.read("Fake_Apple_TV"), setup.record

        Airplay.sync do
          connection = Airplay::Pairing::Connection.new(host: "127.0.0.1", port: receiver.port).open
          begin
            verify = Airplay::Pairing::Verify.new(store.read("Fake_Apple_TV")).run(connection)
            assert connection.encrypted?
            refute_nil verify.shared_secret
          ensure
            connection.close
          end
        end
      end
    end
  end

  def test_a_missing_password_surfaces_auth_required_with_the_device
    with_receiver(pairing: {}) do |receiver|
      error = assert_raises(Airplay::AuthRequiredError) do
        Airplay.sync { Airplay::Pairing::Setup.pair(receiver.device, transient: false) }
      end

      assert_equal :auth_required, error.code
      assert_equal receiver.device.name, error.device
      assert_empty receiver.exchanges
    end
  end

  def test_a_wrong_password_surfaces_auth_failed_with_the_device
    Dir.mktmpdir do |dir|
      store = Airplay::Pairing::CredentialStore.new(directory: dir)

      with_receiver(pairing: { pin: "1234" }) do |receiver|
        error = assert_raises(Airplay::AuthFailedError) do
          Airplay.sync do
            Airplay::Pairing::Setup.pair(receiver.device, code: "0000", transient: false,
                                                        store: store, attempts: 1)
          end
        end

        assert_equal :auth_failed, error.code
        assert_equal receiver.device.name, error.device
        assert_empty Dir.children(dir)
      end
    end
  end

  def test_a_rejected_pairing_surfaces_auth_failed_with_the_device
    with_receiver(pairing: { accept: false }) do |receiver|
      error = assert_raises(Airplay::AuthFailedError) do
        Airplay.sync { Airplay::Pairing::Setup.pair(receiver.device, attempts: 1) }
      end

      assert_equal :auth_failed, error.code
      assert_equal receiver.device.name, error.device
    end
  end

  def test_a_refused_connection_surfaces_connect_failed_with_the_device
    server = TCPServer.new("127.0.0.1", 0)
    port = server.addr[1]
    server.close
    device = Airplay::Device.new(name: "Gone", host: "127.0.0.1", port: port)

    error = assert_raises(Airplay::TransportError) do
      Airplay.sync { Airplay::Pairing::Setup.pair(device, attempts: 1) }
    end

    assert_equal :connect_failed, error.code
    assert_equal "Gone", error.device
  end

  def test_a_tag_failure_surfaces_auth_failed_with_the_device
    Dir.mktmpdir do |dir|
      store = Airplay::Pairing::CredentialStore.new(directory: dir)

      with_receiver(pairing: { pin: "1234", info_body: Airplay::Plist.dump("name" => "Fake"),
                               faults: { corrupt_tag: true } }) do |receiver|
        Airplay.sync do
          Airplay::Pairing::Setup.pair(receiver.device, code: "1234", transient: false, store: store)
        end

        error = assert_raises(Airplay::AuthFailedError) do
          Airplay.sync do
            Airplay::Control::Session.open(receiver.device, store: store, timing_port: 7001)
          end
        end

        assert_equal :auth_failed, error.code
        assert_equal receiver.device.name, error.device
      end
    end
  end

  def test_deferred_mechanisms_fail_with_unsupported_feature
    Dir.mktmpdir do |dir|
      { "fp-setup" => "FairPlay", "auth-setup" => "MFi", "accessory" => "HAP accessory mode" }
        .each do |demand, name|
        with_receiver(pairing: { demand: demand }) do |receiver|
          error = assert_raises(Airplay::UnsupportedError) do
            Airplay.sync { Airplay::Pairing::Setup.pair(receiver.device, attempts: 1) }
          end

          assert_equal :unsupported_feature, error.code
          assert_includes error.message, name
        end
      end

      assert_empty Dir.children(dir)
    end
  end
end
