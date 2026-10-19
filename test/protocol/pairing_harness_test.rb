require "test_helper"
require "io/stream"
require "socket"

class PairingHarnessTest < Airplay::TestCase
  NOTES = File.read(File.expand_path("../../lib/airplay/fake_device/NOTES.md", __dir__))

  def test_a_transient_pair_setup_completes_after_two_requests
    responses = { "/pair-setup" => [{ 6 => "\x02".b, 2 => "salt".b, 3 => "public".b }] }

    with_receiver(pairing: { responses: responses }) do |receiver|
      Airplay.sync do
        Airplay::Session.open(receiver.device) do |session|
          first = decode(session.post("/pair-setup", body: encode(6 => "\x01".b, 0 => "\x00".b),
                                                     headers: { "X-Apple-HKP" => "4" }))
          second = decode(session.post("/pair-setup", body: encode(6 => "\x03".b, 3 => "A".b, 4 => "proof".b),
                                                      headers: { "X-Apple-HKP" => "4" }))

          assert_equal "\x02".b, value(first, 6)
          assert_equal "salt".b, value(first, 2)
          assert_equal "public".b, value(first, 3)
          assert_equal "\x04".b, value(second, 6)
        end
      end

      assert receiver.pairing_complete?
      assert_equal 2, receiver.pairing_messages["/pair-setup"].length
      assert_equal "proof".b, value(receiver.pairing_messages["/pair-setup"].last, 4)
    end
  end

  def test_a_pin_pair_setup_completes_after_three_requests
    responses = { "/pair-setup" => [nil, nil, { 6 => "\x06".b, 1 => "accessory".b }] }

    with_receiver(pairing: { responses: responses }) do |receiver|
      Airplay.sync do
        Airplay::Session.open(receiver.device) do |session|
          [1, 3, 5].each do |state|
            decode(session.post("/pair-setup", body: encode(6 => [state].pack("C")),
                                                      headers: { "X-Apple-HKP" => "3" }))
          end
        end
      end

      assert receiver.pairing_complete?
      assert_equal 3, receiver.pairing_messages["/pair-setup"].length
    end
  end

  def test_a_pair_verify_exchange_completes_after_two_requests
    responses = { "/pair-verify" => [nil, { 6 => "\x04".b, 5 => "encrypted".b }] }

    with_receiver(pairing: { responses: responses }) do |receiver|
      Airplay.sync do
        Airplay::Session.open(receiver.device) do |session|
          session.post("/pair-verify", body: encode(6 => "\x01".b, 3 => "public".b))
          last = decode(session.post("/pair-verify", body: encode(6 => "\x03".b, 5 => "ciphertext".b)))

          assert_equal "\x04".b, value(last, 6)
          assert_equal "encrypted".b, value(last, 5)
        end
      end

      assert receiver.verified?
      assert_equal 2, receiver.pairing_messages["/pair-verify"].length
    end
  end

  def test_a_rejected_pairing_reports_the_scripted_error
    with_receiver(pairing: { accept: false }) do |receiver|
      response = Airplay.sync do
        Airplay::Session.open(receiver.device) do |session|
          decode(session.post("/pair-setup", body: encode(6 => "\x01".b, 0 => "\x00".b)))
        end
      end

      assert_equal "\x01".b, value(response, 6)
      assert_equal "\x02".b, value(response, 7)
      refute receiver.pairing_complete?
    end
  end

  def test_a_plaintext_request_after_pair_verify_closes_the_connection
    with_receiver(pairing: {}) do |receiver|
      error = nil

      Airplay.sync do
        Airplay::Session.open(receiver.device) do |session|
          pair_verify(session)
          error = assert_raises(Airplay::TransportError) { session.get("/info") }
        end
      end

      assert_equal :connection_lost, error.code
      assert receiver.verified?
    end
  end

  def test_a_framed_request_is_served_after_pair_verify
    with_receiver(pairing: { control_write_key: WRITE_KEY, control_read_key: READ_KEY }) do |receiver|
      Airplay.sync do
        stream = verified_stream(receiver)
        begin
          stream.write(Airplay::Pairing::Frame.new(WRITE_KEY).encrypt(
                         "GET /info HTTP/1.1\r\nhost: 127.0.0.1\r\ncontent-length: 0\r\n\r\n"
                       ), flush: true)
          plaintext = Airplay::Pairing::Frame.new(READ_KEY).decrypt(read_frame(stream))

          assert_includes plaintext, "HTTP/1.1 200"
          assert_equal "/info", receiver.exchanges.last.path
        ensure
          stream.close
        end
      end
    end
  end

  def test_a_wrong_pin_knob_rejects_the_proof
    with_receiver(pairing: { faults: { wrong_pin: true } }) do |receiver|
      reply = nil

      Airplay.sync do
        Airplay::Session.open(receiver.device) do |session|
          session.post("/pair-setup", body: encode(6 => "\x01".b, 0 => "\x00".b),
                                      headers: { "X-Apple-HKP" => "4" })
          reply = decode(session.post("/pair-setup", body: encode(6 => "\x03".b, 4 => "proof".b),
                                                     headers: { "X-Apple-HKP" => "4" }))
        end
      end

      assert_equal "\x02".b, value(reply, 7)
      refute receiver.pairing_complete?
    end
  end

  def test_a_401_knob_challenges_the_first_control_request
    with_receiver(pairing: { control_write_key: WRITE_KEY, control_read_key: READ_KEY,
                             faults: { control_401: true } }) do |receiver|
      Airplay.sync do
        stream = verified_stream(receiver)
        begin
          stream.write(Airplay::Pairing::Frame.new(WRITE_KEY).encrypt(
                         "GET /info HTTP/1.1\r\nhost: 127.0.0.1\r\ncontent-length: 0\r\n\r\n"
                       ), flush: true)
          response = Airplay::Pairing::Frame.new(READ_KEY).decrypt(read_frame(stream))

          assert_includes response, "HTTP/1.1 401"
        ensure
          stream.close
        end
      end
    end
  end

  def test_a_corrupted_tag_knob_fails_authentication
    with_receiver(pairing: { control_write_key: WRITE_KEY, control_read_key: READ_KEY,
                             faults: { corrupt_tag: true } }) do |receiver|
      Airplay.sync do
        stream = verified_stream(receiver)
        begin
          stream.write(control_request, flush: true)

          assert_raises(Airplay::AuthFailedError) do
            Airplay::Pairing::Frame.new(READ_KEY).decrypt(read_frame(stream))
          end
        ensure
          stream.close
        end
      end
    end
  end

  def test_a_replayed_counter_knob_sends_the_same_frame_twice
    with_receiver(pairing: { control_write_key: WRITE_KEY, control_read_key: READ_KEY,
                             faults: { replayed_counter: true } }) do |receiver|
      Airplay.sync do
        stream = verified_stream(receiver)
        reader = Airplay::Pairing::Frame.new(READ_KEY)
        begin
          stream.write(control_request, flush: true)
          first = read_frame(stream)
          second = read_frame(stream)

          assert_equal first, second
          assert_includes reader.decrypt(first), "HTTP/1.1 200"
          assert_raises(Airplay::AuthFailedError) { reader.decrypt(second) }
        ensure
          stream.close
        end
      end
    end
  end

  def test_a_truncated_frame_knob_ends_the_connection_mid_frame
    with_receiver(pairing: { control_write_key: WRITE_KEY, control_read_key: READ_KEY,
                             faults: { truncated_frame: true } }) do |receiver|
      Airplay.sync do
        stream = verified_stream(receiver)
        begin
          stream.write(control_request, flush: true)
          header = stream.read_exactly(2)
          length = header.unpack1("v")

          assert_raises(EOFError) do
            stream.read_exactly(length + Airplay::Pairing::Frame::TAG_LENGTH)
          end
        ensure
          stream.close
        end
      end
    end
  end

  def test_an_oversized_length_knob_declares_more_than_the_frame_maximum
    with_receiver(pairing: { control_write_key: WRITE_KEY, control_read_key: READ_KEY,
                             faults: { oversized_length: true } }) do |receiver|
      Airplay.sync do
        stream = verified_stream(receiver)
        begin
          stream.write(control_request, flush: true)

          assert_operator stream.read_exactly(2).unpack1("v"), :>,
                          Airplay::Pairing::Frame::MAX_LENGTH
        ensure
          stream.close
        end
      end
    end
  end

  def test_a_wedge_knob_ignores_bytes_and_accepts_a_retry_connection
    with_receiver(pairing: { faults: { wrong_pin: true, wedge: true } }) do |receiver|
      Airplay.sync do
        stream = IO::Stream(Socket.tcp("127.0.0.1", receiver.port))
        retry_stream = nil
        begin
          stream.write(http_request("POST", "/pair-setup", encode(6 => "\x01".b, 0 => "\x00".b)), flush: true)
          read_http_response(stream)
          stream.write(http_request("POST", "/pair-setup", encode(6 => "\x03".b, 4 => "proof".b)), flush: true)
          read_http_response(stream)

          stream.write("GET /info HTTP/1.1\r\nhost: 127.0.0.1\r\n\r\n", flush: true)
          assert_raises(Async::TimeoutError) do
            Async::Task.current.with_timeout(0.2) { stream.read_until("\r\n") }
          end
          assert_equal 2, receiver.exchanges.length

          retry_stream = IO::Stream(Socket.tcp("127.0.0.1", receiver.port))
          retry_stream.write(http_request("POST", "/pair-setup", encode(6 => "\x01".b, 0 => "\x00".b)), flush: true)
          status, = read_http_response(retry_stream)

          assert_includes status, "200"
          assert_equal 2, receiver.connections
        ensure
          stream.close
          retry_stream&.close
        end
      end
    end
  end

  def test_a_scripted_info_body_is_served
    info = Airplay::Plist.dump("name" => "Scripted")

    with_receiver(pairing: { control_write_key: WRITE_KEY, control_read_key: READ_KEY,
                             info_body: info }) do |receiver|
      Airplay.sync do
        stream = verified_stream(receiver)
        begin
          stream.write(control_request, flush: true)
          response = Airplay::Pairing::Frame.new(READ_KEY).decrypt(read_frame(stream))

          assert_includes response, "application/x-apple-binary-plist"
          assert_equal "Scripted", Airplay::Plist.load(response.split("\r\n\r\n", 2).last)["name"]
        ensure
          stream.close
        end
      end
    end
  end

  def test_a_trivial_session_records_requests_with_plists_and_connections
    body = Airplay::Plist.dump("volume" => -15.0)

    with_receiver(pairing: { control_write_key: WRITE_KEY, control_read_key: READ_KEY }) do |receiver|
      Airplay.sync do
        stream = verified_stream(receiver)
        begin
          stream.write(Airplay::Pairing::Frame.new(WRITE_KEY).encrypt(
                         "POST /command HTTP/1.1\r\nhost: 127.0.0.1\r\ncontent-length: #{body.bytesize}\r\n\r\n#{body}"
                       ), flush: true)
          read_frame(stream)

          exchange = receiver.exchanges.last
          assert_equal "POST", exchange.method
          assert_equal "/command", exchange.path
          assert_equal(-15.0, exchange.plist["volume"])
          assert_same receiver.exchanges.first.connection, exchange.connection
        ensure
          stream.close
        end
      end
    end
  end

  def test_the_harness_exposes_a_clock_and_feedback_interval
    clock = Airplay::FakeDevice::FakeClock.new

    with_receiver(pairing: { clock: clock, feedback_interval: 5 }) do |receiver|
      assert_same clock, receiver.clock
      assert_equal 5, receiver.feedback_interval

      receiver.clock.advance(5)
      assert_equal 5.0, receiver.clock.now
    end
  end

  def test_scripted_events_are_delivered_on_the_reverse_connection
    event_key = "e" * 32
    server = TCPServer.new("127.0.0.1", 0)

    with_receiver(pairing: { control_write_key: WRITE_KEY, control_read_key: READ_KEY,
                             event_target: ["127.0.0.1", server.addr[1]],
                             event_write_key: event_key,
                             events: [{ "type" => "stop" }] }) do |receiver|
      Airplay.sync do
        listener = Async::Task.current.async do
          client = server.accept
          begin
            stream = IO::Stream(client)
            header = stream.read_exactly(2)
            length = header.unpack1("v")
            Airplay::Plist.load(Airplay::Pairing::Frame.new(event_key).decrypt(
              header + stream.read_exactly(length + Airplay::Pairing::Frame::TAG_LENGTH)
            ))
          ensure
            stream&.close
          end
        end

        stream = verified_stream(receiver)
        begin
          assert_equal "stop", listener.wait["type"]
        ensure
          stream.close
        end
      end
    end
  ensure
    server&.close
  end

  def test_the_knob_notes_match_the_exposed_constants
    receiver = Airplay::FakeDevice::Receiver
    expected = (receiver::PAIRING_DEFAULTS.keys + [:faults] + receiver::PAIRING_FAULTS).sort

    assert_equal expected, receiver::PAIRING_OPTIONS.sort
    receiver::PAIRING_OPTIONS.each do |name|
      assert_includes NOTES, "`#{name}`", "NOTES.md does not document #{name}"
    end
  end

  private

  WRITE_KEY = "w" * 32
  READ_KEY = "r" * 32

  def pair_verify(session)
    session.post("/pair-verify", body: encode(6 => "\x01".b, 3 => "public".b))
    session.post("/pair-verify", body: encode(6 => "\x03".b, 5 => "ciphertext".b))
  end

  def verified_stream(receiver)
    stream = IO::Stream(Socket.tcp("127.0.0.1", receiver.port))
    2.times do |step|
      body = encode(6 => [step * 2 + 1].pack("C"), 3 => "public".b)
      stream.write(http_request("POST", "/pair-verify", body), flush: true)
      read_http_response(stream)
    end
    stream
  end

  def control_request
    Airplay::Pairing::Frame.new(WRITE_KEY).encrypt(
      "GET /info HTTP/1.1\r\nhost: 127.0.0.1\r\ncontent-length: 0\r\n\r\n"
    )
  end

  def read_frame(stream)
    header = stream.read_exactly(2)
    length = header.unpack1("v")

    header + stream.read_exactly(length + Airplay::Pairing::Frame::TAG_LENGTH)
  end

  def http_request(method, path, body)
    "#{method} #{path} HTTP/1.1\r\nhost: 127.0.0.1\r\ncontent-length: #{body.bytesize}\r\n\r\n#{body}".b
  end

  def read_http_response(stream)
    status = stream.read_until("\r\n")
    headers = {}
    while (line = stream.read_until("\r\n")) && !line.empty?
      name, value = line.split(":", 2)
      headers[name.to_s.downcase] = value.to_s.strip
    end

    [status, headers, stream.read_exactly(headers["content-length"].to_i)]
  end

  def encode(items)
    Airplay::Pairing::TLV8.encode(
      items.map { |type, value| Airplay::Pairing::TLV8::Item.new(type, value) }
    )
  end

  def decode(response)
    Airplay::Pairing::TLV8.decode(response.body)
  end

  def value(items, type)
    items.find { |item| item.type == type }&.value
  end
end
