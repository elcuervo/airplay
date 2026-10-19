require "async"
require "async/http"
require "json"
require "openssl"
require "securerandom"
require "socket"

require "airplay"
require "airplay/fake_device/fake_clock"

module Airplay
  module FakeDevice
    # Public: In-process AirPlay receiver double used by the protocol lane.
    class Receiver
      Exchange = Struct.new(:method, :path, :headers, :body, :plist, :connection, keyword_init: true)
      Record = Struct.new(:name, :model, :features, :password, keyword_init: true)
      Request = Struct.new(:method, :path, :headers, :body, :connection, keyword_init: true)

      DEFAULT_RECORD = {
        name: "Fake Apple TV",
        model: "AppleTV6,2",
        features: 0,
        password: nil
      }.freeze

      attr_reader :record, :exchanges, :faults, :port, :pairing_messages, :clock, :events,
                  :control_keys, :event_keys, :pairings, :framed_requests, :parameters
      attr_accessor :connections, :feedback_interval

      PAIRING_PATHS = %w[/pair-setup /pair-verify].freeze
      PAIRING_REQUESTS = { transient: 2, pin: 3 }.freeze
      PAIRING_VERIFY_REQUESTS = 2
      PAIRING_DEFAULTS = {
        accept: true,
        pin: "1234",
        responses: {},
        rejection: nil,
        control_write_key: nil,
        control_read_key: nil,
        info_body: nil,
        setup_body: nil,
        demand: nil,
        clock: nil,
        feedback_interval: nil,
        events: [],
        event_target: nil,
        event_write_key: nil
      }.freeze
      PAIRING_FAULTS = %i[
        wrong_pin control_401 corrupt_tag replayed_counter truncated_frame oversized_length wedge
      ].freeze
      PAIRING_OPTIONS = (PAIRING_DEFAULTS.keys + [:faults] + PAIRING_FAULTS).freeze

      def initialize(record: {}, faults: {}, pairing: nil)
        @record = Record.new(**DEFAULT_RECORD.merge(record))
        @faults = faults.dup
        @exchanges = []
        @connections = 0
        @pairing = pairing && PAIRING_DEFAULTS.merge(pairing)
        @clock = @pairing && (@pairing[:clock] || FakeClock.new)
        @feedback_interval = @pairing && @pairing[:feedback_interval]
        @events = @pairing ? Array(@pairing[:events]) : []
        @pairing_messages = Hash.new { |hash, key| hash[key] = [] }
        @pairing_flow = :transient
        @pairing_rejected = false
        @wrong_pin_rejected = false
        @pairings = {}
        @framed_requests = 0
        @last_feedback_at = nil
        @parameters = {}
        @accessory_key = @pairing && OpenSSL::PKey.generate_key("Ed25519")
        @accessory_identifier = @pairing && SecureRandom.uuid
        @bound = nil
        @server = nil
        @task = nil
      end

      def start
        endpoint = Async::HTTP::Endpoint.parse("http://127.0.0.1:0")
        @bound = endpoint.bound
        @port = @bound.sockets.first.to_io.local_address.ip_port
        http_endpoint = Async::HTTP::Endpoint.parse(url, @bound)
        @server = Server.new(method(:handle), http_endpoint, receiver: self)
        @task = Async::Task.current.async { @server.run }
        self
      end

      def stop
        @task&.stop
        @bound&.close
        @task = nil
        @server = nil
        self
      end

      def url
        "http://127.0.0.1:#{port}"
      end

      def device(**options)
        Airplay::Device.new(name: record.name, host: "127.0.0.1", port: port,
                            model: record.model, **options)
      end

      def handle(request)
        index = @exchanges.size + 1
        body = request.body
        body = body.join if body.respond_to?(:join)
        @exchanges << Exchange.new(
          method: request.method,
          path: request.path,
          headers: request.headers.to_h.transform_values do |value|
            value.is_a?(Array) && value.length == 1 ? value.first : value
          end,
          body: body,
          plist: decode_plist(body),
          connection: request.respond_to?(:connection) ? request.connection : nil
        )

        fault = @faults[index] || {}
        if @pairing && @pairing[:demand]
          return respond(403, "", { "x-airplay-auth" => @pairing[:demand] })
        end
        return handle_pairing(request, body) if @pairing && PAIRING_PATHS.include?(request.path)
        if @pairing && request.path == "/info" && @pairing[:info_body]
          return respond(200, @pairing[:info_body],
                         { "content-type" => "application/x-apple-binary-plist" })
        end
        if @pairing && request.path == "/setup"
          setup = decode_plist(body)
          @last_feedback_at = @clock.now
          deliver_events(setup)
          return respond(200, setup_response(setup),
                         { "content-type" => "application/x-apple-binary-plist" })
        end

        if @pairing && request.method == "SET_PARAMETER"
          @parameters = @parameters.merge(decode_plist(body) || {})
          return respond(200, "")
        end

        case fault[:kind]
        when :delay
          sleep(fault.fetch(:seconds, 1))
          respond(200, record_json)
        when :status
          respond(fault.fetch(:status, 500), "error")
        when :auth
          respond(401, "", { "www-authenticate" => %(Digest realm="raop", nonce="fake") })
        when :truncate
          body = record_json
          respond(200, body[0, body.length / 2],
                  { "content-length" => body.bytesize.to_s })
        when :corrupt
          body = record_json
          respond(200, body.sub(/\A\{/, "["))
        else
          respond(200, record_json)
        end
      end

      def connection_fault
        @faults[:connection]
      end

      # Public: True once the pairing exchange on `path` has received all its messages.
      def pairing_complete?(path = "/pair-setup")
        return false unless @pairing
        return false if @pairing_rejected

        @pairing_messages[path].length >= expected_pairing_requests(path)
      end

      # Public: True once the scripted pair-verify exchange has received all four messages.
      def verified?
        pairing_complete?("/pair-verify")
      end

      private

      def handle_pairing(request, body)
        items = Airplay::Pairing::TLV8.decode(body.to_s)
        state = tlv_value(items, 6)&.getbyte(0)
        path = request.path

        if state == 1
          @pairing_messages[path] = []
          @pairing_rejected = false
          @control_keys = @event_keys = nil
          @pairing_flow = pairing_flow(request.headers) if path == "/pair-setup"
        end
        @pairing_messages[path] << items

        wrong_pin = fault?(:wrong_pin) && path == "/pair-setup" &&
                    @pairing_messages[path].length >= 2 && !@wrong_pin_rejected
        rejected = !@pairing[:accept] || wrong_pin
        @wrong_pin_rejected = true if wrong_pin
        @pairing_rejected = rejected
        reply = rejected ? pairing_rejection(items) : pairing_body(path, items)
        rejected = @pairing_rejected

        response = respond(200, reply, { "content-type" => "application/octet-stream" })
        return wedged_session(request, response) if rejected && fault?(:wedge)
        return encrypted_session(request, response) if encrypt_now?(path)

        response
      end

      def encrypt_now?(path)
        return true if path == "/pair-verify" && pairing_complete?(path)
        return true if path == "/pair-setup" && @pairing_flow == :transient && pairing_complete?(path)

        false
      end

      def fault?(name)
        @pairing.dig(:faults, name)
      end

      def wedged_session(request, response)
        return response unless request.respond_to?(:hijack?) && request.hijack?

        stream = request.hijack!
        stream.write(serialize(response), flush: true)
        loop { stream.read_exactly(1) }
      rescue EOFError, Airplay::Error, SystemCallError, IOError
        nil
      ensure
        stream&.close
      end

      # Public: Takes over the connection after pair-verify and serves AEAD-framed requests.
      def encrypted_session(request, response)
        return response unless request.respond_to?(:hijack?) && request.hijack?

        stream = request.hijack!
        stream.write(serialize(response), flush: true)
        deliver_events if @pairing[:event_target]
        read_frames(stream, request.connection)
        nil
      end

      def deliver_events(setup = nil)
        explicit = @pairing[:event_target]
        port = setup && setup["eventPort"]
        return unless explicit || port

        host, port = explicit || ["127.0.0.1", port]
        stream = IO::Stream(Socket.tcp(host, port))
        writer = Airplay::Pairing::Frame.new((@pairing[:event_write_key] || @event_keys&.first).to_s)
        @events.each do |event|
          bytes = event.is_a?(String) ? event : Airplay::Plist.dump(event)
          stream.write(writer.encrypt(bytes), flush: true)
        end
      rescue SystemCallError, IOError
        nil
      ensure
        stream&.close
      end

      def read_frames(stream, connection)
        reader = Airplay::Pairing::Frame.new((@control_keys&.first || @pairing[:control_write_key]).to_s)
        writer = Airplay::Pairing::Frame.new((@control_keys&.last || @pairing[:control_read_key]).to_s)
        injected = false

        loop do
          header = stream.read_exactly(2)
          length = header.unpack1("v")
          return if length > Airplay::Pairing::Frame::MAX_LENGTH

          plaintext = reader.decrypt(header + stream.read_exactly(length + Airplay::Pairing::Frame::TAG_LENGTH))
          @framed_requests += 1
          return if feedback_overdue?

          request = parse_request(plaintext, connection)
          @last_feedback_at = @clock.now if request.path == "/feedback"
          bytes = writer.encrypt(serialize(control_response(request)))
          fault = injected ? nil : framed_fault
          injected ||= !fault.nil?

          return inject_frame_fault(stream, bytes, fault) if fault

          stream.write(bytes, flush: true)
        end
      rescue EOFError, Airplay::Error, SystemCallError, IOError
        nil
      ensure
        stream.close
      end

      def control_response(request)
        response = handle(request)
        if fault?(:control_401) && !@control_challenged
          @control_challenged = true
          return respond(401, "", { "www-authenticate" => %(Digest realm="airplay", nonce="fake") })
        end

        response
      end

      def framed_fault
        %i[corrupt_tag replayed_counter truncated_frame oversized_length].find { |name| fault?(name) }
      end

      def inject_frame_fault(stream, bytes, fault)
        case fault
        when :corrupt_tag
          bytes.setbyte(-1, bytes.getbyte(-1) ^ 0xFF)
          stream.write(bytes, flush: true)
        when :replayed_counter
          stream.write(bytes + bytes, flush: true)
        when :truncated_frame
          stream.write(bytes.byteslice(0, bytes.bytesize - Airplay::Pairing::Frame::TAG_LENGTH), flush: true)
        when :oversized_length
          stream.write([Airplay::Pairing::Frame::MAX_LENGTH + 1].pack("v"), flush: true)
        end
      end

      # shortcut: one frame carries one complete request; split frames when a sender chunks requests.
      def parse_request(bytes, connection = nil)
        head, _, body = bytes.to_s.b.partition("\r\n\r\n")
        method, path, = head.split("\r\n", 2).first.to_s.split(" ")
        headers = head.split("\r\n").drop(1).each_with_object({}) do |line, hash|
          name, value = line.split(":", 2)
          hash[name.to_s.strip.downcase] = value.to_s.strip
        end

        Request.new(method: method, path: path, headers: headers, body: body, connection: connection)
      end

      def setup_response(request)
        body = @pairing[:setup_body] || {
          "timingProtocol" => request&.fetch("timingProtocol", "NTP") || "NTP",
          "timingPort" => request&.fetch("timingPort", 0) || 0,
          "feedbackInterval" => @pairing[:feedback_interval] || 2
        }

        body.is_a?(Hash) ? Airplay::Plist.dump(body) : body
      end

      def feedback_overdue?
        interval = @pairing[:feedback_interval]
        return false unless interval && @last_feedback_at

        @clock.now - @last_feedback_at > interval
      end

      def decode_plist(body)
        return nil unless body.is_a?(String) && body.start_with?(Airplay::Plist::Binary::HEADER)

        Airplay::Plist.load(body)
      rescue Airplay::ProtocolError
        nil
      end

      def serialize(response)
        body = response.read.to_s.b
        headers = response.headers.to_h.transform_values { |value| Array(value).join(", ") }
        headers["content-length"] = body.bytesize.to_s
        lines = ["HTTP/1.1 #{response.status}"] +
                headers.map { |name, value| "#{name}: #{value}" }

        lines.join("\r\n") + "\r\n\r\n" + body
      end

      def pairing_flow(headers)
        headers["x-apple-hkp"].to_s == "3" ? :pin : :transient
      end

      def pairing_body(path, items)
        return responder_body(path, items) if responder?(path)

        step = @pairing_messages[path].length - 1
        script = Array(@pairing[:responses][path])[step]
        script = script.call(items) if script.respond_to?(:call)
        return pairing_rejection(items) if script == :reject
        return script.b if script.is_a?(String)

        encode_tlv(script || { 6 => [@pairing_messages[path].length * 2].pack("C") })
      end

      def responder?(path)
        return false unless Array(@pairing[:responses][path]).empty?
        return true if path == "/pair-setup"

        path == "/pair-verify" && @pairings.any?
      end

      def responder_body(path, items)
        return verify_response(items) if path == "/pair-verify"

        case tlv_value(items, 6)&.getbyte(0)
        when 1
          @srp = Pairing::SRP::Verifier.new(pin: pairing_pin)
          encode_tlv(6 => "\x02".b, 2 => @srp.salt, 3 => padded(@srp.public))
        when 3
          key = @srp&.verify(tlv_value(items, 3), tlv_value(items, 4))
          unless key
            @pairing_rejected = true
            return pairing_rejection(items)
          end

          @srp_key = key
          @pair_setup_key = Pairing::HKDF.expand(key, salt: "Pair-Setup-Encrypt-Salt",
                                                      info: "Pair-Setup-Encrypt-Info")
          derive_keys(key)
          encode_tlv(6 => "\x04".b, 4 => @srp.server_proof)
        when 5
          pair_identity_response(items)
        else
          @pairing_rejected = true
          pairing_rejection(items)
        end
      end

      def pair_identity_response(items)
        identity = Pairing::TLV8.decode(
          Pairing::AEAD.decrypt(key: @pair_setup_key, nonce: Pairing::AEAD.nonce("PS-Msg05"),
                                ciphertext: tlv_value(items, 5))
        )
        identifier = tlv_value(identity, 1)
        client_public = tlv_value(identity, 3)
        material = Pairing::HKDF.expand(@srp_key, salt: "Pair-Setup-Controller-Sign-Salt",
                                                 info: "Pair-Setup-Controller-Sign-Info") +
                   identifier + client_public

        unless Pairing::Keys.ed25519_public(client_public).verify(nil, tlv_value(identity, 10), material)
          @pairing_rejected = true
          return pairing_rejection(items)
        end

        @pairings[identifier] = client_public
        encode_tlv(6 => "\x06".b, 5 => sealed_identity)
      rescue Airplay::Error
        @pairing_rejected = true
        pairing_rejection(items)
      end

      def sealed_identity
        accessory_public = Pairing::Keys.raw_public(@accessory_key)
        material = Pairing::HKDF.expand(@srp_key, salt: "Pair-Setup-Accessory-Sign-Salt",
                                                 info: "Pair-Setup-Accessory-Sign-Info") +
                   @accessory_identifier + accessory_public
        signature = @accessory_key.sign(nil, material)

        Pairing::AEAD.encrypt(
          key: @pair_setup_key, nonce: Pairing::AEAD.nonce("PS-Msg06"),
          plaintext: Pairing::TLV8.encode([
            Pairing::TLV8::Item.new(1, @accessory_identifier),
            Pairing::TLV8::Item.new(3, accessory_public),
            Pairing::TLV8::Item.new(10, signature)
          ])
        )
      end

      def verify_response(items)
        case tlv_value(items, 6)&.getbyte(0)
        when 1
          @client_curve_public = tlv_value(items, 3)
          @verify_key = OpenSSL::PKey.generate_key("X25519")
          @verify_public = Pairing::Keys.raw_public(@verify_key)
          @verify_shared = @verify_key.derive(Pairing::Keys.x25519_public(@client_curve_public))
          @verify_encryption_key = Pairing::HKDF.expand(@verify_shared, salt: "Pair-Verify-Encrypt-Salt",
                                                                     info: "Pair-Verify-Encrypt-Info")
          signature = @accessory_key.sign(nil, @verify_public + @accessory_identifier + @client_curve_public)
          sealed = Pairing::AEAD.encrypt(
            key: @verify_encryption_key, nonce: Pairing::AEAD.nonce("PV-Msg02"),
            plaintext: Pairing::TLV8.encode([
              Pairing::TLV8::Item.new(1, @accessory_identifier),
              Pairing::TLV8::Item.new(10, signature)
            ])
          )
          encode_tlv(6 => "\x02".b, 3 => @verify_public, 5 => sealed)
        when 3
          identity = Pairing::TLV8.decode(
            Pairing::AEAD.decrypt(key: @verify_encryption_key, nonce: Pairing::AEAD.nonce("PV-Msg03"),
                                  ciphertext: tlv_value(items, 5))
          )
          identifier = tlv_value(identity, 1)
          client_public = @pairings[identifier]
          material = @client_curve_public + identifier.to_s + @verify_public
          unless client_public && Pairing::Keys.ed25519_public(client_public)
                                                    .verify(nil, tlv_value(identity, 10), material)
            @pairing_rejected = true
            return pairing_rejection(items)
          end

          @control_keys = Pairing::HKDF.control_keys(@verify_shared)
          @event_keys = Pairing::HKDF.event_keys(@verify_shared)
          encode_tlv(6 => "\x04".b)
        else
          @pairing_rejected = true
          pairing_rejection(items)
        end
      rescue Airplay::Error
        @pairing_rejected = true
        pairing_rejection(items)
      end

      def pairing_pin
        @pairing_flow == :transient ? Pairing::Setup::TRANSIENT_CODE : @pairing[:pin].to_s
      end

      def padded(value)
        value.to_s(2).rjust(Pairing::SRP::GROUP_BYTES, "\0")
      end

      def derive_keys(key)
        return unless @pairing_flow == :transient

        @control_keys = Pairing::HKDF.control_keys(key)
        @event_keys = Pairing::HKDF.event_keys(key)
      end

      def pairing_rejection(items)
        encode_tlv(@pairing[:rejection] || { 6 => tlv_value(items, 6) || "\x01".b, 7 => "\x02".b })
      end

      def expected_pairing_requests(path)
        return PAIRING_VERIFY_REQUESTS if path == "/pair-verify"

        PAIRING_REQUESTS.fetch(@pairing_flow)
      end

      def tlv_value(items, type)
        items.find { |item| item.type == type }&.value
      end

      def encode_tlv(script)
        Airplay::Pairing::TLV8.encode(
          script.map { |type, value| Airplay::Pairing::TLV8::Item.new(type, value.to_s.b) }
        )
      end

      def record_json
        JSON.generate(
          name: record.name,
          model: record.model,
          features: record.features,
          password: !record.password.nil?
        )
      end

      def respond(status, body, headers = {})
        Protocol::HTTP::Response[
          status,
          { "content-type" => "application/json" }.merge(headers),
          [body]
        ]
      end

      # Public: Applies connection-level faults before the HTTP protocol runs.
      class Server < Async::HTTP::Server
        def initialize(app, endpoint, receiver:)
          super(app, endpoint)
          @receiver = receiver
        end

        def accept(peer, address, task: Async::Task.current)
          @receiver.connections += 1

          case @receiver.connection_fault
          when :drop
            peer.close
            nil
          when :reset
            io = peer.respond_to?(:to_io) ? peer.to_io : peer
            io.setsockopt(Socket::SOL_SOCKET, Socket::SO_LINGER, [1, 0].pack("ii"))
            io.close
            nil
          else
            super
          end
        end
      end
    end
  end
end
