require "test_helper"
require "socket"

class SessionProtocolTest < Airplay::TestCase
  def test_reads_the_configured_record
    with_receiver(record: { name: "Living Room", model: "AppleTV6,2", features: 42 }) do |receiver|
      body = Airplay.sync do
        Airplay::Session.open(receiver.device) { |session| session.get("/record").body }
      end

      record = JSON.parse(body)
      assert_equal "Living Room", record["name"]
      assert_equal 42, record["features"]

      exchange = receiver.exchanges.first
      assert_equal "GET", exchange.method
      assert_equal "/record", exchange.path
    end
  end

  def test_session_releases_its_resources
    with_receiver do |receiver|
      session = nil

      Airplay.sync do
        Airplay::Session.open(receiver.device) do |open|
          session = open
          open.get("/record")
        end
      end

      assert session.closed?
      refute session.children.any?(&:alive?)
      assert_raises(Airplay::SessionClosedError) { session.get("/record") }
    end
  end

  def test_a_stalled_device_times_out
    with_receiver(faults: { 1 => { kind: :delay, seconds: 1 } }) do |receiver|
      error = assert_raises(Airplay::TimeoutError) do
        Airplay.sync do
          Airplay::Session.open(receiver.device, timeout: 0.1) do |session|
            session.get("/record")
          end
        end
      end

      assert_equal :timeout, error.code
    end
  end

  def test_a_refused_connection_is_a_transport_error
    socket = TCPServer.new("127.0.0.1", 0)
    port = socket.local_address.ip_port
    socket.close

    device = Airplay::Device.new(name: "gone", host: "127.0.0.1", port: port)
    error = assert_raises(Airplay::TransportError) do
      Airplay.sync { Airplay::Session.open(device) { |session| session.get("/") } }
    end

    assert_equal :connection_refused, error.code
  end

  def test_cancellation_stops_child_tasks
    with_receiver do |receiver|
      Airplay.sync do
        session = Airplay::Session.new(receiver.device)
        child = session.spawn do
          loop { sleep(0.01) }
        end

        session.cancel

        refute child.alive?
        assert session.closed?
      end
    end
  end

  def test_slow_resolution_does_not_block_a_peer
    with_receiver do |receiver|
      Airplay.resolver = SlowResolver.new("slow.invalid", 0.5)

      Airplay.sync do |task|
        slow = task.async do
          device = Airplay::Device.new(name: "slow", host: "slow.invalid", port: 7000)
          Airplay::Session.open(device) { |session| session.get("/") }
        end

        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        Airplay::Session.open(receiver.device) { |session| session.get("/record") }
        elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started

        assert_operator elapsed, :<, 0.3
        slow.stop
      end
    end
  end

  def test_a_raising_session_does_not_stop_a_peer
    with_receiver do |receiver|
      Airplay.sync do |task|
        peer = task.async do
          Airplay::Session.open(receiver.device) { |session| session.get("/record").body }
        end

        assert_raises(RuntimeError) do
          Airplay::Session.open(receiver.device) { raise "boom" }
        end

        assert_equal receiver.record.name, JSON.parse(peer.wait)["name"]
      end
    end
  end

  def test_sync_facade_matches_a_manual_reactor
    with_receiver do |receiver|
      manual = Airplay.sync do
        Airplay::Session.open(receiver.device) { |session| session.get("/record").body }
      end
      facade = Airplay.open(receiver.device) { |session| session.get("/record").body }

      assert_equal manual, facade
    end
  end

  class SlowResolver < Airplay::Resolver
    def initialize(slow_host, delay)
      @slow_host = slow_host
      @delay = delay
    end

    def resolve(host, port)
      Kernel.sleep(@delay) if host == @slow_host
      [["127.0.0.1", port]]
    end
  end
end
