require "async"
require "async/http"
require "digest"
require "openssl"
require "securerandom"
require "socket"
require "uri"

require "airplay/errors"
require "airplay/media"
require "airplay/media/server"
require "airplay/media/snapshot"
require "airplay/media/state"
require "airplay/plist"
require "airplay/resolver"
require "airplay/status"

module Airplay
  # Public: One device interaction, owning its connection and child tasks.
  class Session
    Response = Struct.new(:status, :headers, :body, keyword_init: true)
    USER_AGENT = "MediaControl/1.0"
    TRANSITIONS = %w[None Dissolve SlideLeft SlideRight].freeze

    attr_reader :device, :id, :timeout, :children, :playlist, :information,
                :snapshot, :state, :media_server

    def self.open(device, timeout: nil, task: Async::Task.current, base_url: nil, **options)
      raise ArgumentError, "block required" unless block_given?

      session = new(device, timeout: timeout, task: task, base_url: base_url, **options)
      begin
        yield session
      ensure
        session.close
      end
    end

    def initialize(device, timeout: nil, task: Async::Task.current, base_url: nil,
                   password: nil, digest_username: nil, legacy: false, capabilities: nil)
      if capabilities&.airplay2? && !legacy
        raise Airplay::UnsupportedError.new(
          "this device uses the AirPlay 2 route; pass legacy: true to force AirPlay 1",
          code: :unsupported_feature
        )
      end

      @device = device
      @timeout = timeout || Airplay.configuration.timeout
      @task = task
      @id = SecureRandom.uuid
      @children = []
      @inflight = []
      @closed = false
      @base_url = base_url && URI.parse(base_url)
      @base_path = @base_url ? @base_url.path.to_s.chomp("/") : ""
      @password = password || device.password
      @digest_username = digest_username
      @playlist = Media::Playlist.new
      @state = Media::State.new
      @subscriptions = []
      @device_identifier = "0x#{SecureRandom.hex(6)}"
      @identity_headers = {
        "user-agent" => USER_AGENT,
        "x-apple-session-id" => @id,
        "x-apple-device-id" => @device_identifier
      }
      if capabilities&.password_required? && !@password
        Status.emit("session.password_hint", level: :warn, device: device.name)
      end

      @client = build_client

      Status.emit("session.open", session_id: id, device: device.name,
                                  host: device.host, port: device.port)
    end

    def closed?
      @closed
    end

    def get(path, headers: nil, retryable: false, **options)
      request("GET", path, headers: headers, retryable: retryable, **options)
    end

    def post(path, body: nil, headers: nil, **options)
      request("POST", path, body: body, headers: headers, **options)
    end

    def put(path, body: nil, headers: nil, **options)
      request("PUT", path, body: body, headers: headers, **options)
    end

    def request(method, path, headers: nil, body: nil, timeout: @timeout, retryable: false)
      raise SessionClosedError, "session #{id} is closed" if @closed

      target = join_path(path)
      response = perform(method, target, headers, body, timeout)

      if response.status == 401
        response = authenticate(method, target, headers, body, timeout, response)
      end

      response
    rescue Airplay::TransportError
      raise unless retryable

      reconnect
      perform(method, target, headers, body, timeout)
    end

    # Public: Decodes GET /server-info, preserving every reported key.
    def server_info
      response = get("/server-info", retryable: true)
      expect!(response, Airplay::ProtocolError)
      @information = decode_plist(response.body)
      unless @information.is_a?(Hash)
        raise Airplay::ProtocolError.new("server info is not a property list dictionary",
                                         code: :malformed_plist)
      end

      @information
    end

    # Public: Reads GET /playback-info into a snapshot.
    def playback_info
      response = get("/playback-info", retryable: true)
      expect!(response, Airplay::ProtocolError)
      @snapshot = Media::Snapshot.new(decode_plist(response.body))
    end

    # Public: Reads GET /scrub or seeks with POST /scrub?position=<seconds>.
    def scrub(position = nil)
      if position.nil?
        response = get("/scrub", retryable: true)
        expect!(response, Airplay::ProtocolError)
        parse_parameters(response.body)
      else
        unless position.to_f >= 0
          raise Airplay::PlaybackError.new("scrub position must not be negative", code: :playback_error)
        end

        expect!(post("/scrub?position=#{position}"), Airplay::PlaybackError)
      end
    end

    # Public: Displays a picture with one of the documented transitions.
    def photo(picture, transition: "None")
      unless TRANSITIONS.include?(transition)
        raise Airplay::PlaybackError.new("unknown transition #{transition.inspect}", code: :playback_error)
      end

      bytes, type = Airplay::Picture.resolve(picture, session: self)
      response = put("/photo", body: bytes,
                              headers: { "content-type" => type, "x-apple-transition" => transition })
      expect!(response, Airplay::PlaybackError)
    end

    # Public: Starts playback of a URL, a local file or the playlist's next item.
    def play(media = nil, position: 0.0)
      unless position.to_f.between?(0.0, 1.0)
        raise Airplay::PlaybackError.new("start position must be within 0.0..1.0", code: :playback_error)
      end

      location = case media
                 when nil then (@queued || playlist.next_item)&.url
                 when Media::Media then media.url || publish(media.source)
                 else publish_if_file(media)
                 end
      unless location
        raise Airplay::PlaybackError.new("nothing to play", code: :playback_error)
      end

      body = "Content-Location: #{location}\r\nStart-Position: #{position}\r\n"
      expect!(post("/play", body: body, headers: { "content-type" => "text/parameters" }),
              Airplay::PlaybackError)
    end

    def rate(value)
      expect!(post("/rate?value=#{value}"), Airplay::PlaybackError)
    end

    def stop
      expect!(post("/stop"), Airplay::PlaybackError)
    end

    def set_property(name, value)
      response = put("/setProperty?#{name}", body: Airplay::Plist.dump(value),
                                               headers: { "content-type" => "application/x-apple-binary-plist" })
      expect!(response, Airplay::PlaybackError)
      answer = decode_plist(response.body) rescue nil
      code = answer && answer["errorCode"]
      if code && code.to_i != 0
        raise Airplay::PlaybackError.new("receiver rejected property with #{code}", code: code.to_i)
      end

      answer
    end

    # Public: Fetches an absolute URL outside the device origin.
    def fetch(url)
      uri = URI.parse(url)
      client = Async::HTTP::Client.new(
        Async::HTTP::Endpoint.parse("#{uri.scheme}://#{uri.host}:#{uri.port}")
      )
      begin
        request = Protocol::HTTP::Request["GET", uri.request_uri]
        response = Async::Task.current.with_timeout(@timeout) { client.call(request) }
        Response.new(status: response.status, headers: response.headers, body: response.read)
      ensure
        client.close
      end
    rescue Async::TimeoutError
      raise TimeoutError.new("fetch #{url} timed out after #{@timeout}s", code: :timeout)
    rescue Errno::ECONNREFUSED
      raise TransportError.new("connection refused by #{uri.host}:#{uri.port}", code: :connection_refused)
    rescue Errno::ECONNRESET, Errno::EPIPE, EOFError, IOError => e
      raise TransportError.new("fetch #{url} failed: #{e.message}", code: :connection_lost)
    end

    # Public: Publishes a local file, reusing the session's media server.
    def publish(path)
      raise Airplay::PlaybackError.new("cannot publish #{path}", code: :playback_error) unless File.exist?(path)

      media_server.publish(path)
    end

    def media_server
      @media_server ||= Media::Server.new(host: advertised_host,
                                          port: Airplay.configuration.media_port || 0)
    end

    # Public: Polls once when the interval has elapsed; returns the snapshot or nil.
    def poll(interval: 1.0)
      return nil if @closed

      now = Airplay.clock.now
      return nil if @last_poll && now - @last_poll < interval

      @last_poll = now
      snapshot = playback_info
      previous = @state.current
      @state.handle(snapshot)
      @queued = playlist.next_item if @state.current == :played && previous != :played
      @queued = nil if @state.current != :played
      @subscriptions.each { |subscription| subscription.push(snapshot) }
      snapshot
    end

    def progress(interval: 1.0)
      subscription = Subscription.new(interval: interval, session: self)
      @subscriptions << subscription
      subscription
    end

    def wait(interval: 1.0)
      loop do
        snapshot = poll(interval: interval)
        unless snapshot
          Airplay.clock.sleep(interval)
          next
        end
        break if @state.current == :played
      end
      true
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
      @subscriptions.each(&:close)
      @children.each { |child| child.stop if child.alive? }
      @media_server&.stop
      @client.close
      Status.emit("session.close", session_id: id)
    end

    private

    def build_client
      if @base_url
        Async::HTTP::Client.new(Async::HTTP::Endpoint.parse(@base_url.to_s), retries: 0)
      else
        host, port = Airplay.resolver.resolve_without_blocking(device.host, device.port).first
        Async::HTTP::Client.new(Async::HTTP::Endpoint.parse("http://#{host}:#{port}"), retries: 0)
      end
    end

    def reconnect
      @client.close
      @client = build_client
    end

    def join_path(path)
      joined = "#{@base_path}/#{path.to_s.delete_prefix("/")}"
      joined.empty? ? "/" : joined
    end

    def perform(method, target, headers, body, timeout)
      request_task = @task.async do
        request = Protocol::HTTP::Request[method, target, merge_headers(headers), body]
        @client.call(request)
      end
      @inflight << request_task

      response = Async::Task.current.with_timeout(timeout) { request_task.wait }
      payload = response.read
      Response.new(status: response.status, headers: response.headers, body: payload)
    rescue Async::TimeoutError
      raise TimeoutError.new("#{method} #{target} timed out after #{timeout}s", code: :timeout)
    rescue Errno::ECONNREFUSED
      raise TransportError.new("connection refused by #{device.address}", code: :connection_refused)
    rescue SocketError
      raise TransportError.new("cannot resolve #{device.host}", code: :dns_failure)
    rescue Errno::ECONNRESET, Errno::EPIPE, EOFError, IOError => e
      raise TransportError.new("connection to #{device.address} lost: #{e.message}", code: :connection_lost)
    rescue Protocol::HTTP::Error => e
      raise ProtocolError.new("HTTP protocol failure: #{e.message}", code: :http_protocol)
    ensure
      if request_task
        @inflight.delete(request_task)
        request_task.stop if request_task.alive?
      end
      response&.close
    end

    def merge_headers(headers)
      merged = @identity_headers.dup
      (headers || {}).each { |name, value| merged[name.to_s.downcase] = value.to_s }
      merged
    end

    def authenticate(method, target, headers, body, timeout, response)
      challenge = response.headers["www-authenticate"].to_s
      unless @password
        raise AuthRequiredError.new("#{method} #{target} requires authentication",
                                    code: :auth_required, status: 401)
      end

      unless challenge.start_with?("Digest")
        raise AuthenticationError.new("#{method} #{target} uses #{challenge.split(" ").first} authentication",
                                      code: :authentication_error, status: 401)
      end

      authorization = digest_authorization(challenge, method, target)
      replayed = perform(method, target, (headers || {}).merge("authorization" => authorization),
                         body, timeout)
      if replayed.status == 401
        raise AuthFailedError.new("#{method} #{target} rejected the credentials",
                                  code: :auth_failed, status: 401)
      end

      replayed
    end

    def digest_authorization(challenge, method, target)
      params = challenge.scan(/(\w+)=(?:"([^"]*)"|([^\s,]+))/).to_h { |key, quoted, plain| [key, quoted || plain] }
      realm = params["realm"] || ""
      nonce = params["nonce"] || ""
      username = @digest_username || (realm == "raop" ? "iTunes" : "Airplay")
      ha1 = Digest::MD5.hexdigest("#{username}:#{realm}:#{@password}")
      ha2 = Digest::MD5.hexdigest("#{method}:#{target}")
      fields = %(username="#{username}", realm="#{realm}", nonce="#{nonce}", uri="#{target}")

      if params["qop"]
        nc = "00000001"
        cnonce = SecureRandom.hex(8)
        digest = Digest::MD5.hexdigest("#{ha1}:#{nonce}:#{nc}:#{cnonce}:auth:#{ha2}")
        "Digest #{fields}, qop=auth, nc=#{nc}, cnonce=\"#{cnonce}\", response=\"#{digest}\""
      else
        digest = Digest::MD5.hexdigest("#{ha1}:#{nonce}:#{ha2}")
        "Digest #{fields}, response=\"#{digest}\""
      end
    end

    def expect!(response, error_class)
      return response if response.status.between?(200, 299)

      raise error_class.new("receiver answered #{response.status}", status: response.status)
    end

    def decode_plist(body)
      body = body.to_s
      return Airplay::Plist.load(body) if body.start_with?("bplist00")

      parsed = Airplay::Plist.load_xml(body)
      if parsed.nil?
        raise Airplay::ProtocolError.new("body is not a property list", code: :malformed_plist)
      end

      parsed
    rescue Airplay::ProtocolError, StandardError => error
      raise Airplay::ProtocolError.new("body is not a property list: #{error.message}", code: :malformed_plist)
    end

    def parse_parameters(body)
      values = body.to_s.split("\r\n").each_with_object({}) do |line, result|
        name, value = line.split(":", 2)
        next unless value

        text = value.strip
        result[name.strip] = Float(text)
      rescue ArgumentError
        result[name.strip] = text
      end
      raise Airplay::ProtocolError.new("body is not a parameter list", code: :malformed_parameters) if values.empty?

      values
    end

    def publish_if_file(value)
      return value unless value.is_a?(String) && File.file?(value)

      publish(value)
    end

    def advertised_host
      Airplay.configuration.advertised_address ||
        Socket.ip_address_list.find { |address| address.ipv4? && !address.ipv4_loopback? }&.ip_address ||
        "127.0.0.1"
    end

    # Public: One progress subscription fed by the session's sampler.
    class Subscription
      def initialize(interval:, session:)
        @interval = interval
        @session = session
        @values = []
        @closed = false
      end

      def push(value)
        @values << value
      end

      def size
        @values.size
      end

      def close
        @closed = true
      end

      def each
        loop do
          if @values.any?
            yield @values.shift
          elsif @closed
            break
          else
            @session.poll(interval: @interval)
            Airplay.clock.sleep(0.01) if @values.empty?
          end
        end
      end
    end
  end
end
