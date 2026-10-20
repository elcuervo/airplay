require "async"
require "async/http"
require "uri"

require "airplay"

module Airplay
  module FakeDevice
    # Public: Play-queue receiver mode: recording, expectations, scripts and faults.
    module QueueMode
      BINARY = { "content-type" => "application/x-apple-binary-plist" }.freeze
      DEFAULTS = {
        stream_id: 77,
        stream_status: 403,
        refuse_stream: false,
        playback_info: [],
        expectations: nil,
        strict_order: false,
        feedback_overlap: false,
        feedback_pending: false,
        snapshot: nil,
        reject_update: nil,
        faults: {}
      }.freeze
      SCRIPTS = {
        replacement: %w[playing loading playing],
        paused: %w[playing paused],
        stopped: %w[playing stopped],
        none: []
      }.freeze
      QUEUE_PATHS = %w[/record /command /feedback].freeze

      Fetch = Struct.new(:url, :method, :range, :status, :headers, :body, :error,
                         keyword_init: true)

      class ExpectationError < StandardError; end

      def queue_mode?
        !@queue.nil?
      end

      def queue_exchanges
        @exchanges.select { |exchange| queue_request?(exchange) }
      end

      def expect_requests(list)
        @queue[:expectations] = Array(list)
      end

      # Public: Raises at the first divergence, naming it, and for extra requests.
      def verify_expectations!
        expected = Array(@queue[:expectations])
        actual = queue_exchanges
        expected.each_with_index do |want, index|
          got = actual[index]
          next if got && matches?(want, got)

          raise ExpectationError.new(
            "expected #{describe(want)} at position #{index + 1}, " \
            "got #{got ? describe(got) : 'no request'}"
          )
        end
        return true if actual.length <= expected.length

        raise ExpectationError.new(
          "unexpected request #{describe(actual[expected.length])} at position #{expected.length + 1}"
        )
      end

      # Public: Pushes a scripted transition sequence; :none pushes nothing.
      def script(name)
        states = SCRIPTS.fetch(name.to_sym) do
          raise ArgumentError, "unknown script #{name.inspect}; known: #{SCRIPTS.keys.inspect}"
        end
        states.each { |state| push_state(state) }
        states
      end

      def push_state(value, **fields)
        push_event("type" => "event", "value" => fields.merge("state" => value.to_s))
      end

      def push_event(payload)
        push_event_body(Airplay::Plist.dump(payload))
        payload
      end

      # Public: Pushes an arbitrary event body, for undecodable-message checks.
      def push_event_body(body)
        return nil unless @event_stream

        body = body.to_s.b
        head = "POST /event HTTP/1.1\r\ncontent-type: application/x-apple-binary-plist\r\n" \
               "content-length: #{body.bytesize}\r\n\r\n".b
        bytes = head + body
        offset = 0
        while offset < bytes.bytesize
          chunk = bytes.byteslice(offset, Airplay::Pairing::Frame::MAX_LENGTH)
          @event_stream.write(@event_writer.encrypt(chunk), flush: true)
          offset += chunk.bytesize
        end
        @event_acks += 1 if read_event_ack
        body
      end

      # Public: Records a fetch of a URL the sender handed the receiver.
      def fetch_media(url, range: nil, method: "GET")
        uri = URI.parse(url)
        client = Async::HTTP::Client.new(
          Async::HTTP::Endpoint.parse("#{uri.scheme}://#{uri.host}:#{uri.port}")
        )
        request = Protocol::HTTP::Request[method, uri.request_uri]
        request.headers["range"] = range if range
        response = client.call(request)
        record = Fetch.new(url: url, method: method, range: range, status: response.status,
                           headers: response.headers.to_h, body: response.read)
        @media_fetches << record
        record
      rescue StandardError => error
        record = Fetch.new(url: url, method: method, range: range, error: error.message)
        @media_fetches << record
        record
      ensure
        client&.close
      end

      # Internal: Handles the queue-mode requests after recording the exchange.
      def handle_queue(request)
        return nil unless queue_mode?

        return queue_info if request.path == "/info"
        return respond(200, Airplay::Plist.dump({}), BINARY) if request.path == "/record"
        return queue_command(request) if request.path == "/command"
        return queue_playback_info if request.path == "/playback-info"

        nil
      end

      def feedback_outstanding?
        @feedback_outstanding
      end

      def stream_registered?
        @stream_registered
      end

      private

      # Internal: A plaintext /info before pairing verification is an ordering violation.
      def queue_plaintext_violation?(request)
        queue_mode? && @queue[:strict_order] && request.path == "/info" &&
          !request.is_a?(Airplay::FakeDevice::Receiver::Request)
      end

      def queue_plaintext_drop(request)
        stream = request.hijack! if request.respond_to?(:hijack?) && request.hijack?
        stream&.close
        nil
      end

      def queue_info
        info = {
          "name" => record.name,
          "model" => record.model,
          "deviceid" => record.model == "AppleTV6,2" ? "AA:BB:CC:DD:EE:FF" : record.name,
          "srcvers" => record.srcvers,
          "features" => format("0x%x", record.features.to_i)
        }.compact
        respond(200, Airplay::Plist.dump(info), BINARY)
      end

      def queue_stream_response
        if @queue[:refuse_stream]
          return respond(@queue[:stream_status] || 403, "")
        end

        @stream_registered = true
        stream = { "type" => 130 }
        identifier = @queue.key?(:stream_id) ? @queue[:stream_id] : DEFAULTS[:stream_id]
        stream["streamID"] = identifier unless identifier.nil?
        respond(200, Airplay::Plist.dump("streams" => [stream]), BINARY)
      end

      # Internal: Decodes the nested command payload; nil when the body is bare.
      def nested_command(body)
        outer = decode_plist(body)
        return nil unless outer.is_a?(Hash)

        nested = outer["command"]
        return nil unless nested.is_a?(Airplay::Plist::Data)

        Airplay::Plist.load(nested.bytes)
      rescue Airplay::Error
        nil
      end

      def queue_command(request)
        exchange = @exchanges.last
        command = exchange.command
        return respond(400, "") if command.nil?

        @commands << command
        status = command_status(command)
        return respond(status, "") unless status == 200

        answer_snapshot(command) if command["type"].to_s == "getPlaybackState"
        respond(200, Airplay::Plist.dump({}), BINARY)
      end

      # Internal: Faults are keyed by command type (retry-safe) or request index.
      def command_status(command)
        if @queue[:reject_update] && command["type"] == "updateNowPlayingInfo" &&
           command.dig("params", "mergePolicy") == "update"
          return @queue[:reject_update]
        end

        faults = @queue[:faults] || {}
        after_insert = faults[:after_insert]
        return after_insert if after_insert && @commands.length > 1

        fault = faults[command["type"].to_s] || faults[@commands.length]
        case fault
        when Integer then fault
        when Hash
          remaining = (@fault_budget[fault.object_id] ||= fault.fetch(:times, 1))
          return 200 if remaining.zero?

          @fault_budget[fault.object_id] = remaining - 1
          fault[:status] || 500
        else 200
        end
      end

      def answer_snapshot(command)
        return if @queue[:snapshot] == :absent

        identifier = command.dig("params", "requestID") || command.dig("params", "id")
        return if identifier.nil?

        payload = { "type" => "response", "id" => identifier,
                    "value" => { "state" => @queue[:snapshot] || "playing" } }
        push_event(payload)
      end

      def queue_playback_info
        answer = @queue[:playback_info].shift
        case answer
        when :playing
          respond(200, Airplay::Plist.dump("rate" => 1.0, "duration" => 100.0,
                                           "position" => 5.0, "readyToPlay" => true), BINARY)
        when :empty then respond(200, "", BINARY)
        when :error then respond(500, "")
        when Hash
          respond(answer[:status] || 200, answer[:body] || Airplay::Plist.dump(answer[:plist] || {}),
                  BINARY)
        else respond(200, answer.to_s, BINARY)
        end
      end

      def queue_request?(exchange)
        return true if QUEUE_PATHS.include?(exchange.path)

        exchange.path == "/setup" && exchange.plist.is_a?(Hash) && exchange.plist["streams"]
      end

      def matches?(want, got)
        return false if want[:method] && want[:method].to_s != got.method
        return false if want[:path] && want[:path] != got.path

        headers = want[:headers] || {}
        headers.all? { |name, value| got.headers[name.to_s.downcase].to_s == value.to_s } &&
          (want[:plist].nil? || want[:plist] == got.plist) &&
          (want[:command].nil? || want[:command] == got.command)
      end

      def describe(entry)
        if entry.is_a?(Hash)
          "#{entry[:method] || entry['method']} #{entry[:path] || entry['path']} " \
            "#{(entry[:command] || entry['command']).inspect}"
        else
          "#{entry.method} #{entry.path} #{entry.command.inspect}"
        end
      end

      # Internal: True when the receiver is configured to drop the connection.
      def queue_order_violation?(request)
        return false unless queue_mode?

        if @queue[:strict_order]
          return true if request.path == "/command" && !@stream_registered
          return true if request.path == "/feedback" && !@recorded
        end

        @queue[:feedback_overlap] && request.path == "/command" && @feedback_outstanding
      end

      def note_queue_request(request)
        @feedback_outstanding = true if request.path == "/feedback"
        @recorded = true if request.path == "/record"
      end

      def read_event_ack
        header = @event_stream.read_exactly(2)
        length = header.unpack1("v")
        return false if length > Airplay::Pairing::Frame::MAX_LENGTH

        @event_reader.decrypt(header + @event_stream.read_exactly(length + Airplay::Pairing::Frame::TAG_LENGTH))
        true
      rescue EOFError, SystemCallError, IOError
        false
      end
    end
  end
end
