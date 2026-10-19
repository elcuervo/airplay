require "test_helper"
require "tmpdir"

class LoggingTest < Airplay::TestCase
  INFO = { "name" => "Fake", "features" => "0x40000000000" }.freeze

  def test_pairing_routing_and_reconciliation_leave_no_secrets_in_the_log
    Dir.mktmpdir do |dir|
      store = Airplay::Pairing::CredentialStore.new(directory: dir)

      with_receiver(pairing: { pin: "1234", info_body: Airplay::Plist.dump(INFO) }) do |receiver|
        setup = nil

        Airplay.sync do
          connection = Airplay::Pairing::Connection.new(host: "127.0.0.1", port: receiver.port).open
          begin
            setup = Airplay::Pairing::Setup.new(code: "1234", transient: false, store: store,
                                                device: "Fake_Apple_TV")
            setup.run(connection)
            verify = Airplay::Pairing::Verify.new(store.read("Fake_Apple_TV")).run(connection)
            Airplay::Route.decide({ features: (1 << 38) | (1 << 46), credentials: true })
            Airplay::Control::Session.new(connection, timing_port: 7001,
                                                      event_key: verify.event_keys.first).establish
          ensure
            connection.close
          end
        end

        log = @output.string
        assert_includes log, "pairing.setup"
        assert_includes log, "pairing.ready"
        assert_includes log, "route.decide"
        assert_includes log, "capabilities.reconcile"

        record = store.read("Fake_Apple_TV")
        refute_includes log, "1234"
        refute_includes log, setup.key.unpack1("H*")
        refute_includes log, record["client_private"].bytes.unpack1("H*")
        refute_includes log, record["accessory_signature"].bytes.unpack1("H*")
      end
    end
  end
end
