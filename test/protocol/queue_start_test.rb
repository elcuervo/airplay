require "test_helper"
require "json"

class QueueStartTest < Airplay::TestCase
  PROFILE = Airplay::Queue::Profile::TVOS_26_5
  URL = "http://example.com/movie.mp4"

  def test_the_start_sequence_is_sent_in_order
    with_queue_session do |receiver, session|
      route = build_route(session)
      receiver.expect_requests([
        { method: "POST", path: "/setup" },
        { method: "POST", path: "/command" },
        { method: "POST", path: "/command" },
        { method: "POST", path: "/command" },
        { method: "POST", path: "/command" }
      ])

      route.play(URL)

      assert_equal %w[insertPlayQueueItem setProperty setProperty setRate],
                   receiver.commands.map { |command| command["type"] }
      assert_equal %w[isInterestedInDateRange actionAtItemEnd],
                   receiver.commands.select { |c| c["type"] == "setProperty" }
                                   .map { |c| c.dig("params", "name") }
      assert_equal 1.0, receiver.commands.last.dig("params", "rate")
      assert receiver.verify_expectations!
    end
  end

  def test_the_inserted_item_carries_every_declared_field
    with_queue_session do |receiver, session|
      route = build_route(session)
      route.play(URL, position: 12.5)

      insert = receiver.commands.first
      params = insert["params"]
      assert_equal route.item_id, params["uuid"]
      assert_equal URL, params["url"]
      assert_equal "file", params["mediaType"]
      assert_equal false, params["secure"]
      assert_equal 12.5, params["startPosition"]
      refute receiver.commands.any? { |command| command["type"] == "seekToTime" }
    end
  end

  def test_a_failing_insert_stops_the_sequence
    with_queue_session(queue: { faults: { "insertPlayQueueItem" => 500 } }) do |receiver, session|
      error = assert_raises(Airplay::ProtocolError) { build_route(session).play(URL) }

      assert_equal 500, error.status
      types = receiver.commands.map { |c| c["type"] }
      assert_equal %w[insertPlayQueueItem insertPlayQueueItem insertPlayQueueItem], types
      refute_includes types, "setProperty"
    end
  end

  def test_a_failing_property_stops_the_sequence
    with_queue_session(queue: { faults: { "setProperty" => 500 } }) do |receiver, session|
      assert_raises(Airplay::ProtocolError) { build_route(session).play(URL) }

      assert_equal %w[insertPlayQueueItem setProperty], receiver.commands.map { |c| c["type"] }
    end
  end

  def test_a_failing_rate_stops_the_sequence
    with_queue_session(queue: { faults: { "setRate" => 500 } }) do |receiver, session|
      assert_raises(Airplay::ProtocolError) { build_route(session).play(URL) }

      assert_equal %w[insertPlayQueueItem setProperty setProperty setRate],
                   receiver.commands.map { |c| c["type"] }
    end
  end

  def test_queue_manipulation_uses_the_command_endpoint
    with_queue_session do |receiver, session|
      route = build_route(session)
      first = route.play(URL)
      added = route.add("http://example.com/second.mp4")
      route.remove(added)
      route.next
      route.previous

      types = receiver.commands.map { |command| command["type"] }
      assert_includes types, "removePlayQueueItem"
      assert_includes types, "selectQueueItem"
      assert_equal added, receiver.commands.find { |c| c["type"] == "removePlayQueueItem" }
                                   .dig("params", "uuid")
      legacy = receiver.exchanges.map(&:path).select do |path|
        %w[/play /rate /scrub].include?(path)
      end
      assert_empty legacy
      assert first
    end
  end

  def test_each_profile_replays_its_fixture_without_code_changes
    Dir[File.expand_path("../fixtures/queue/*.json", __dir__)].each do |path|
      fixture = JSON.parse(File.read(path))
      profile = Airplay::Queue::Profile::TABLE.find { |candidate| candidate.id == fixture["profile"] }
      insert = fixture["commands"].first

      with_queue_session do |receiver, session|
        session.register_control_stream(profile: profile)
        registration = fixture["registration"]
        setup = receiver.queue_exchanges.find { |exchange| exchange.path == "/setup" }
        entry = setup.plist["streams"].first
        assert_equal registration["type"], entry["type"]
        assert_equal registration["controlType"], entry["controlType"]
        assert_equal registration["clientType"], entry["clientType"]
        assert entry["channelID"]
        assert entry["clientUUID"]

        client = Airplay::Queue::Client.new(session: session, profile: profile,
                                            stream_id: session.stream_id)
        params = insert["params"]
        client.insert(uuid: params["uuid"], url: params["url"], secure: params["secure"],
                      position: params["startPosition"])
        client.property("isInterestedInDateRange", true)
        client.property("actionAtItemEnd", true) if fixture["action_at_item_end"]
        client.rate(1.0)

        assert_equal fixture["commands"], receiver.commands, "profile #{fixture['profile']}"
        headers = receiver.queue_exchanges.select { |e| e.path == "/command" }.map(&:headers)
        assert_equal [profile.sender] * headers.length,
                     headers.map { |head| head["user-agent"] }, "profile #{fixture['profile']}"
        assert headers.all? { |head| head[profile.stream_header].to_s == session.stream_id.to_s }
      end
    end
  end

  private

  def build_route(session, profile: PROFILE)
    Airplay::Player::Queue.new(session: session, profile: profile, media_host: nil, window: 0.1)
  end
end
