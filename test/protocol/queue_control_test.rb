require "test_helper"

class QueueControlTest < Airplay::TestCase
  PROFILE = Airplay::Queue::Profile::TVOS_26_5

  def test_the_control_stream_setup_matches_the_profile
    with_queue_session do |receiver, session|
      session.register_control_stream(profile: PROFILE)

      setup = receiver.queue_exchanges.find { |exchange| exchange.path == "/setup" }
      entry = setup.plist["streams"].first

      assert_equal 130, entry["type"]
      assert_equal 1, entry["controlType"]
      assert_equal PROFILE.client_type, entry["clientType"]
      assert entry["clientUUID"]
      assert entry["channelID"]
      assert_equal 77, session.stream_id
    end
  end

  def test_an_answer_without_a_stream_identifier_raises
    with_queue_session(queue: { stream_id: nil }) do |receiver, session|
      error = assert_raises(Airplay::ProtocolError) do
        session.register_control_stream(profile: PROFILE)
      end

      assert_equal :control_stream, error.code
      assert_nil session.stream_id
      assert_empty receiver.commands
    end
  end

  def test_channel_identity_is_derived_per_receiver
    channel_ids = []
    %w[AA:BB:CC:DD:EE:01 AA:BB:CC:DD:EE:02].each do |device_id|
      info = Airplay::Plist.dump("name" => "Fake", "deviceid" => device_id,
                                 "features" => "0x40000000000", "srcvers" => "870.14.1")
      with_queue_session(pairing: { info_body: info }) do |receiver, session|
        session.register_control_stream(profile: PROFILE)
        setup = receiver.queue_exchanges.find { |exchange| exchange.path == "/setup" }
        channel_ids << [session.channel_id, setup.plist["streams"].first["channelID"]]
      end
    end

    refute_equal channel_ids[0][0], channel_ids[1][0]
    assert_equal channel_ids[0][0], channel_ids[0][1]
    assert_equal "AA:BB:CC:DD:EE:01", channel_ids[0][0]
  end

  def test_setup_ordering_precedes_commands
    with_queue_session do |receiver, session|
      session.record
      session.register_control_stream(profile: PROFILE)
      session.command({ "type" => "setRate", "params" => { "rate" => 1.0 } },
                      stream_id: session.stream_id, profile: PROFILE)

      order = receiver.exchanges.map(&:path)
      assert_operator order.index("/info"), :<, order.index("/setup")
      assert_operator order.index("/setup"), :<, order.index("/record")
      assert_operator order.index("/record"), :<, order.rindex("/setup")
      assert_operator order.rindex("/setup"), :<, order.index("/command")
    end
  end

  def test_reading_info_before_verification_drops_the_connection
    with_queue_session(queue: { strict_order: true }) do |receiver, _session|
      connection = Airplay::Pairing::Connection.new(host: "127.0.0.1", port: receiver.port).open
      error = assert_raises(Airplay::TransportError) { connection.request("GET", "/info") }

      assert_equal :connect_failed, error.code
    ensure
      connection&.close
    end
  end

  def test_feedback_before_the_record_request_drops_the_connection
    with_queue_session(queue: { strict_order: true }, pairing: { feedback_interval: 0 }) do |_receiver, session|
      error = assert_raises(Airplay::TransportError) { session.tick }

      assert_equal :connect_failed, error.code
    end
  end

  def test_no_feedback_is_outstanding_when_a_command_is_issued
    with_queue_session(queue: { feedback_overlap: true }, pairing: { feedback_interval: 0 }) do |receiver, session|
      assert session.tick
      refute receiver.feedback_outstanding?

      client = Airplay::Queue::Client.new(session: session, profile: PROFILE,
                                          stream_id: session.stream_id)
      assert_equal 200, client.command(:rate, { "rate" => 1.0 }).status
    end
  end

  def test_the_control_stream_is_distinct_from_the_media_remote_channel
    with_queue_session do |receiver, session|
      session.register_control_stream(profile: PROFILE)
      entry = receiver.queue_exchanges.find { |exchange| exchange.path == "/setup" }
                     .plist["streams"].first

      assert_equal 1, entry["controlType"]
      assert_equal PROFILE.client_type, entry["clientType"]
      refute_equal "com.apple.mediaremote", entry["clientType"]
    end
  end
end
