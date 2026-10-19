require "test_helper"
require "socket"

class HarnessTest < Airplay::TestCase
  def test_receiver_lifecycle_and_record
    Airplay.sync do
      receiver = Airplay::FakeDevice::Receiver.new(record: { name: "Studio", features: 7 }).start

      assert_operator receiver.port, :>, 0
      assert_equal "Studio", receiver.record.name
      assert_includes receiver.url, receiver.port.to_s

      body = Airplay::Session.open(receiver.device) { |session| session.get("/record").body }
      assert_equal "Studio", JSON.parse(body)["name"]

      receiver.stop
    end
  end

  def test_records_method_path_headers_and_body
    with_receiver do |receiver|
      Airplay.sync do
        Airplay::Session.open(receiver.device) do |session|
          session.post("/command", body: "payload", headers: { "x-test" => "yes" })
        end
      end

      exchange = receiver.exchanges.last
      assert_equal "POST", exchange.method
      assert_equal "/command", exchange.path
      assert_equal "payload", exchange.body
      assert_equal "yes", exchange.headers["x-test"]
    end
  end

  def test_a_status_fault_is_returned_verbatim
    with_receiver(faults: { 1 => { kind: :status, status: 503 } }) do |receiver|
      response = Airplay.sync do
        Airplay::Session.open(receiver.device) { |session| session.get("/record") }
      end

      assert_equal 503, response.status
    end
  end

  def test_an_auth_challenge_without_a_password_is_auth_required
    with_receiver(faults: { 1 => { kind: :auth } }) do |receiver|
      error = assert_raises(Airplay::AuthRequiredError) do
        Airplay.sync do
          Airplay::Session.open(receiver.device) { |session| session.get("/record") }
        end
      end

      assert_equal :auth_required, error.code
    end
  end

  def test_a_rejected_credential_is_auth_failed
    with_receiver(faults: { 1 => { kind: :auth } }) do |receiver|
      device = receiver.device(password: "hunter2")

      error = assert_raises(Airplay::AuthFailedError) do
        Airplay.sync do
          Airplay::Session.open(device) { |session| session.get("/record") }
        end
      end

      assert_equal :auth_failed, error.code
    end
  end

  def test_a_corrupted_response_is_not_valid_json
    with_receiver(faults: { 1 => { kind: :corrupt } }) do |receiver|
      body = Airplay.sync do
        Airplay::Session.open(receiver.device) { |session| session.get("/record").body }
      end

      assert_raises(JSON::ParserError) { JSON.parse(body) }
    end
  end

  def test_a_truncated_response_fails_the_request
    with_receiver(faults: { 1 => { kind: :truncate } }) do |receiver|
      error = assert_raises(Airplay::Error) do
        Airplay.sync do
          Airplay::Session.open(receiver.device) { |session| session.get("/record") }
        end
      end

      assert_includes %i[connection_lost http_protocol], error.code
    end
  end

  def test_a_dropped_connection_fails_the_request
    with_receiver(faults: { connection: :drop }) do |receiver|
      error = assert_raises(Airplay::TransportError) do
        Airplay.sync do
          Airplay::Session.open(receiver.device) { |session| session.get("/record") }
        end
      end

      assert_equal :connection_lost, error.code
    end
  end

  def test_a_reset_connection_fails_the_request
    with_receiver(faults: { connection: :reset }) do |receiver|
      error = assert_raises(Airplay::TransportError) do
        Airplay.sync do
          Airplay::Session.open(receiver.device) { |session| session.get("/record") }
        end
      end

      assert_equal :connection_lost, error.code
    end
  end

  def test_stopping_the_receiver_releases_the_port
    port = nil

    Airplay.sync do
      receiver = Airplay::FakeDevice::Receiver.new.start
      port = receiver.port
      receiver.stop
    end

    assert_raises(Errno::ECONNREFUSED) do
      TCPSocket.new("127.0.0.1", port)
    end
  end
end
