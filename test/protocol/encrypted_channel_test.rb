require "test_helper"
require "tmpdir"

class EncryptedChannelTest < Airplay::TestCase
  def test_a_corrupted_tag_fails_authentication_and_closes
    with_verified_receiver(faults: { corrupt_tag: true }) do |receiver, connection|
      error = assert_raises(Airplay::AuthFailedError) { connection.request("GET", "/info") }

      assert_equal :auth_failed, error.code
      assert_equal 1, receiver.framed_requests
      assert_equal [0, 1], connection.counters
      assert_raises(Airplay::SessionClosedError) { connection.request("GET", "/info") }
    end
  end

  def test_a_replayed_counter_is_rejected
    with_verified_receiver(faults: { replayed_counter: true }) do |receiver, connection|
      assert_equal 200, connection.request("GET", "/info").status

      error = assert_raises(Airplay::AuthFailedError) { connection.request("GET", "/info") }

      assert_equal :auth_failed, error.code
      assert_equal 1, receiver.framed_requests
    end
  end

  def test_an_oversized_length_fails_fast_with_connect_failed
    with_verified_receiver(faults: { oversized_length: true }) do |_receiver, connection|
      error = assert_raises(Airplay::TransportError) { connection.request("GET", "/info") }

      assert_equal :connect_failed, error.code
    end
  end

  def test_a_truncated_frame_fails_with_connect_failed
    with_verified_receiver(faults: { truncated_frame: true }) do |_receiver, connection|
      error = assert_raises(Airplay::TransportError) { connection.request("GET", "/info") }

      assert_equal :connect_failed, error.code
    end
  end

  def test_counters_start_at_zero_and_advance_per_complete_frame
    with_verified_receiver do |receiver, connection|
      assert_equal [0, 0], connection.counters

      connection.request("GET", "/info")
      assert_equal [1, 1], connection.counters
      assert_equal 1, receiver.framed_requests
    end
  end

  def test_a_new_connection_starts_its_counters_at_zero
    Dir.mktmpdir do |dir|
      store = Airplay::Pairing::CredentialStore.new(directory: dir)

      with_receiver(pairing: { pin: "1234" }) do |receiver|
        Airplay.sync do
          first = establish(store, receiver)
          first.request("GET", "/info")
          assert_equal [1, 1], first.counters
          first.close

          second = establish(store, receiver)
          assert_equal [0, 0], second.counters
          assert_equal 200, second.request("GET", "/info").status
          assert_equal [1, 1], second.counters
          second.close
        end
      end
    end
  end

  private

  def with_verified_receiver(faults: {}, **pairing)
    Dir.mktmpdir do |dir|
      store = Airplay::Pairing::CredentialStore.new(directory: dir)

      with_receiver(pairing: { pin: "1234", faults: faults, **pairing }) do |receiver|
        Airplay.sync do
          connection = establish(store, receiver)
          begin
            yield receiver, connection
          ensure
            connection.close
          end
        end
      end
    end
  end

  def establish(store, receiver)
    setup = Airplay::Pairing::Connection.new(host: "127.0.0.1", port: receiver.port).open
    Airplay::Pairing::Setup.new(code: "1234", transient: false, store: store,
                                device: "Fake_Apple_TV").run(setup)
    setup.close

    connection = Airplay::Pairing::Connection.new(host: "127.0.0.1", port: receiver.port).open
    Airplay::Pairing::Verify.new(store.read("Fake_Apple_TV")).run(connection)
    connection
  end
end
