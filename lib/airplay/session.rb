require "async"
require "async/http"
require "securerandom"

require "airplay/errors"
require "airplay/resolver"
require "airplay/status"

module Airplay
  # Public: One device interaction, owning its connection and child tasks.
  class Session
    Response = Struct.new(:status, :headers, :body, keyword_init: true)

    attr_reader :device, :id, :timeout, :children

    def self.open(device, timeout: nil, task: Async::Task.current)
      raise ArgumentError, "block required" unless block_given?

      session = new(device, timeout: timeout, task: task)
      begin
        yield session
      ensure
        session.close
      end
    end

    def initialize(device, timeout: nil, task: Async::Task.current)
      @device = device
      @timeout = timeout || Airplay.configuration.timeout
      @task = task
      @id = SecureRandom.uuid
      @children = []
      @inflight = []
      @closed = false

      host, port = Airplay.resolver.resolve_without_blocking(device.host, device.port).first
      @client = Async::HTTP::Client.new(
        Async::HTTP::Endpoint.parse("http://#{host}:#{port}"),
        retries: 0
      )

      Status.emit("session.open", session_id: id, device: device.name,
                                  host: device.host, port: device.port)
    end

    def closed?
      @closed
    end

    def get(path, headers: nil, **options)
      request("GET", path, headers: headers, **options)
    end

    def post(path, body: nil, headers: nil, **options)
      request("POST", path, body: body, headers: headers, **options)
    end

    def put(path, body: nil, headers: nil, **options)
      request("PUT", path, body: body, headers: headers, **options)
    end

    def request(method, path, headers: nil, body: nil, timeout: @timeout)
      raise SessionClosedError, "session #{id} is closed" if @closed

      response = nil
      request_task = @task.async do
        @client.call(Protocol::HTTP::Request[method, path, headers, body])
      end
      @inflight << request_task

      response = Async::Task.current.with_timeout(timeout) { request_task.wait }
      payload = response.read

      if response.status == 401
        error_class = device.password? ? AuthFailedError : AuthRequiredError
        raise error_class.new("#{method} #{path} requires authentication", code: error_class.code)
      end

      Response.new(status: response.status, headers: response.headers, body: payload)
    rescue Async::TimeoutError
      raise TimeoutError.new(
        "#{method} #{path} timed out after #{timeout}s", code: :timeout
      )
    rescue Errno::ECONNREFUSED
      raise TransportError.new(
        "connection refused by #{device.address}", code: :connection_refused
      )
    rescue SocketError
      raise TransportError.new(
        "cannot resolve #{device.host}", code: :dns_failure
      )
    rescue Errno::ECONNRESET, Errno::EPIPE, EOFError, IOError => e
      raise TransportError.new(
        "connection to #{device.address} lost: #{e.message}", code: :connection_lost
      )
    rescue Protocol::HTTP::Error => e
      raise ProtocolError.new("HTTP protocol failure: #{e.message}", code: :http_protocol)
    ensure
      if request_task
        @inflight.delete(request_task)
        request_task.stop if request_task.alive?
      end
      response&.close
    end

    # Public: Starts a child task owned by this session.
    def spawn(&block)
      raise SessionClosedError, "session #{id} is closed" if @closed

      child = @task.async(&block)
      @children << child
      child
    end

    def cancel
      close
    end

    def close
      return if @closed

      @closed = true
      @inflight.each { |task| task.stop if task.alive? }
      @inflight.clear
      @children.each { |child| child.stop if child.alive? }
      @client.close
      Status.emit("session.close", session_id: id)
    end
  end
end
