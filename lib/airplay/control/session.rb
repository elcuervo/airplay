require "securerandom"

require "airplay/discovery/capabilities"
require "airplay/errors"
require "airplay/plist"
require "airplay/status"

module Airplay
  module Control
    # Public: Authenticated control plane over one paired connection.
    class Session
      IMPLEMENTED_TIMING = %w[NTP].freeze
      DEFAULT_FEEDBACK_INTERVAL = 2
      BINARY_PLIST = { "content-type" => "application/x-apple-binary-plist" }.freeze

      attr_reader :connection, :capabilities, :session_id, :group_id,
                  :timing_protocol, :timing_port, :info, :event_channel,
                  :feedback_interval, :stream_id, :channel_id
      attr_accessor :device_name

      def initialize(connection, capabilities: nil, device_identity: nil,
                     timing_protocol: "NTP", timing_port:, event_key: nil)
        @connection = connection
        @capabilities = capabilities || Airplay::Discovery::Capabilities.new
        @device_identity = device_identity || SecureRandom.uuid
        @session_id = SecureRandom.uuid
        @group_id = SecureRandom.uuid
        @requested_timing = timing_protocol
        @timing_port = timing_port
        @event_channel = event_key && EventChannel.new(event_key, on_event: method(:event_received)).start
        @feedback_interval = DEFAULT_FEEDBACK_INTERVAL
        @closed = false
      end

      def establish
        load_info
        negotiate_timing
        @last_feedback = Airplay.clock.now
        self
      end

      # Public: Opens a fresh paired connection and returns an established session.
      def self.open(device, store:, timing_port:, timing_protocol: "NTP", attempts: 2, **options)
        attempts.times do |attempt|
          connection = Airplay::Pairing::Connection.new(host: device.host, port: device.port).open
          record = store.read(Airplay::Pairing::CredentialStore.key_for(device.name))
          unless record
            connection.close
            raise Airplay::AuthRequiredError.new("no credentials for #{device.name}", code: :auth_required)
          end

          verify = Airplay::Pairing::Verify.new(record).run(connection)
          session = new(connection, timing_port: timing_port, timing_protocol: timing_protocol,
                                    event_key: verify.event_keys.first, **options)
          session.device_name = device.name
          begin
            return session.establish
          rescue Airplay::AuthRequiredError
            session.close
            raise if attempt + 1 >= attempts
          rescue Airplay::Error
            session.close
            raise
          end
        end
      rescue Airplay::Error => error
        raise error.with_device(device.name)
      end

      # Public: Maps the 0.0-1.0 volume linearly onto -30..0 dB.
      def self.decibels_for(volume)
        -30.0 + (30.0 * volume.to_f)
      end

      def volume=(value)
        set_parameter("volume" => self.class.decibels_for(value))
      end

      def metadata=(value)
        set_parameter("metadata" => value)
      end

      def set_parameter(fields)
        request("SET_PARAMETER", "/command", body: Airplay::Plist.dump(fields), headers: BINARY_PLIST)
      end

      # Public: Registers the reverse-channel listener; nil when the channel is absent.
      def on_event(&block)
        @event_listener = block
        self
      end

      # Public: Requests a URL control stream and exposes the identifier it returned.
      def register_control_stream(profile:, client_uuid: nil)
        @channel_id = derive_channel_id(profile)
        entry = {
          "type" => 130,
          "controlType" => 1,
          "clientUUID" => client_uuid || @device_identity,
          "clientType" => profile.client_type,
          "channelID" => @channel_id
        }
        response = request("POST", "/setup", body: Airplay::Plist.dump("streams" => [entry]),
                                               headers: BINARY_PLIST)
        unless response.status == 200
          raise Airplay::ProtocolError.new("control stream SETUP answered #{response.status}",
                                           code: :control_stream, status: response.status)
        end

        payload = begin
          Airplay::Plist.load(response.body)
        rescue Airplay::Error
          nil
        end
        stream = payload.is_a?(Hash) ? Array(payload["streams"]).find { |item| item["type"] == 130 } : nil
        identifier = stream && (stream["streamID"] || stream["streamId"])
        if identifier.nil?
          raise Airplay::ProtocolError.new("control stream SETUP answer carries no stream identifier",
                                           code: :control_stream, status: response.status)
        end

        @stream_id = identifier
      end

      # Public: Sends one command wrapped as a nested binary plist on the control stream.
      def command(payload, stream_id:, profile:)
        nested = Airplay::Plist.dump(payload)
        body = Airplay::Plist.dump("command" => Airplay::Plist::Data.new(nested))
        headers = BINARY_PLIST.merge(
          "user-agent" => profile.sender,
          "x-apple-session-id" => session_id,
          profile.stream_header => stream_id.to_s
        )
        request("POST", "/command", body: body, headers: headers)
      end

      # Public: Sends the receiver's record request.
      def record
        response = request("POST", "/record", body: Airplay::Plist.dump({}), headers: BINARY_PLIST)
        unless response.status.between?(200, 299)
          raise Airplay::TransportError.new("POST /record answered #{response.status}",
                                            code: :connect_failed, status: response.status)
        end

        response
      end

      # Public: Returns [status, payload]; a failing endpoint is data, not a state failure.
      def playback_info_document
        response = request("GET", "/playback-info")
        return [response.status, nil] unless response.status.between?(200, 299)

        body = response.body.to_s
        return [response.status, {}] if body.empty?

        [response.status, Airplay::Plist.load(body)]
      rescue Airplay::Error
        [0, nil]
      end
      alias playback_info playback_info_document

      # Public: Ends the session: closes the event channel, stops feedback and sends no more.
      def teardown
        return if @closed

        request("POST", "/teardown", body: Airplay::Plist.dump({}), headers: BINARY_PLIST)
        close
      end

      def active?
        !@closed
      end

      def events
        @event_channel ? @event_channel.events : []
      end

      def event_port
        @event_channel&.port
      end

      def event_channel_lost?
        @event_channel&.lost?
      end

      # Public: Sends feedback when the receiver's interval has elapsed.
      def tick
        return false unless active?

        @last_feedback ||= Airplay.clock.now
        now = Airplay.clock.now
        return false if now - @last_feedback < feedback_interval

        @last_feedback = now
        request("POST", "/feedback", body: Airplay::Plist.dump("streams" => []), headers: BINARY_PLIST)
        true
      end

      def close
        return if @closed

        @closed = true
        @event_channel&.close
        @connection.close
      end

      # Public: Requests `/info` once and folds it into the capability model.
      def load_info
        return @info if @info

        response = request("GET", "/info")
        unless response.status == 200
          raise Airplay::TransportError.new("GET /info answered #{response.status}", code: :connect_failed)
        end

        @info = Airplay::Plist.load(response.body)
        @capabilities = @capabilities.refresh(@info)
        Airplay::Status.emit("capabilities.reconcile", device: device_name, keys: @info.keys)
      rescue Airplay::Plist::DecodeError
        raise Airplay::TransportError.new("GET /info is not a binary plist", code: :connect_failed)
      end

      # Public: Posts the sender identity and timing request; records the confirmed values.
      def negotiate_timing
        fields = {
          "deviceID" => @device_identity,
          "sessionUUID" => session_id,
          "groupUUID" => group_id,
          "timingProtocol" => @requested_timing,
          "timingPort" => @timing_port
        }
        fields["eventPort"] = event_port if event_port

        response = request("POST", "/setup", body: Airplay::Plist.dump(fields), headers: BINARY_PLIST)
        unless response.status == 200
          raise Airplay::TransportError.new("POST /setup answered #{response.status}", code: :connect_failed)
        end

        payload = Airplay::Plist.load(response.body)
        @timing_protocol = payload["timingProtocol"] || @requested_timing
        @timing_port = payload["timingPort"] || @timing_port
        @feedback_interval = payload["feedbackInterval"] || DEFAULT_FEEDBACK_INTERVAL
        unless IMPLEMENTED_TIMING.include?(@timing_protocol)
          raise Airplay::TimingError.new(
            "receiver confirmed unimplemented timing protocol #{@timing_protocol}", code: :timing_error
          )
        end

        payload
      rescue Airplay::Plist::DecodeError
        raise Airplay::TransportError.new("SETUP response is not a binary plist", code: :connect_failed)
      end

      def event_received(event)
        @event_listener&.call(event)
      rescue StandardError => error
        Airplay::Status.emit("event.handler_failed", error: error.class.name)
      end

      # Internal: Channel identity comes from the receiver or the sender, per profile.
      def derive_channel_id(profile)
        case profile.channel_identity
        when :receiver
          capabilities.identity || capabilities.device_id || @device_identity
        else
          @device_identity
        end
      end

      # Public: Sends one control request; a failure marks the session inactive.
      def request(method, path, **options)
        response = @connection.request(method, path, **options)
        if response.status == 401
          @closed = true
          @connection.close
          raise Airplay::AuthRequiredError.new("#{method} #{path} requires authentication",
                                               code: :auth_required)
        end
        response
      rescue Airplay::Error => error
        @closed = true
        raise error.with_device(device_name)
      end
    end
  end
end
