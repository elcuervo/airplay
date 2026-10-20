require "airplay/errors"
require "airplay/queue/command"

module Airplay
  module Queue
    # Public: Sends queue commands on a session's URL control stream.
    class Client
      DEFAULT_ATTEMPTS = 3
      RETRY_DELAY = 1.0

      attr_reader :session, :profile

      def initialize(session:, profile:, stream_id:, attempts: DEFAULT_ATTEMPTS,
                     delay: RETRY_DELAY, clock: Airplay.clock)
        @session = session
        @profile = profile
        @stream_id = stream_id
        @attempts = attempts
        @delay = delay
        @clock = clock
      end

      # Public: The stream identifier, resolved lazily so registration can come first.
      def stream_id
        @stream_id.respond_to?(:call) ? @stream_id.call : @stream_id
      end

      # Public: Sends one command, retrying only the caller-nominated first command.
      def command(name, params = {}, retryable: false)
        type = profile.commands.fetch(name)
        budget = retryable ? @attempts : 1
        attempt = 1
        payload = { "type" => type, "params" => params }
        loop do
          response = session.command(payload, stream_id: stream_id, profile: profile)
          return response if response.status.between?(200, 299)

          if response.status == 500 && attempt < budget
            attempt += 1
            @clock.sleep(@delay)
            next
          end

          raise failure_for(type, response)
        end
      end

      def insert(uuid:, url:, secure: nil, position: nil, retryable: true)
        params = {
          field(:uuid) => uuid,
          field(:url) => url,
          field(:media_kind) => profile.media_kind,
          field(:secure) => secure.nil? ? url.to_s.start_with?("https") : secure
        }
        params[field(:start_position)] = position.to_f if position && position.to_f.positive?
        command(:insert, params, retryable: retryable)
      end

      def remove(uuid:)
        command(:remove, { field(:uuid) => uuid })
      end

      def select(uuid:)
        command(:select, { field(:uuid) => uuid })
      end

      def rate(value)
        command(:rate, { field(:rate) => value })
      end

      def seek(uuid:, position:)
        command(:seek, { field(:uuid) => uuid, field(:seek_position) => position.to_f })
      end

      def snapshot(request_id:)
        command(:snapshot, { field(:request_id) => request_id })
      end

      def property(name, value)
        command(:property, { field(:property_name) => name, field(:property_value) => value })
      end

      # Public: Sends a command payload and returns its response without classifying it.
      def deliver(payload)
        session.command(payload, stream_id: stream_id, profile: profile)
      end

      private

      def field(name)
        profile.fields.fetch(name)
      end

      def failure_for(type, response)
        case response.status
        when 401
          Airplay::AuthRequiredError.new("#{type} requires authentication",
                                         code: :auth_required, status: 401)
        when 403
          Airplay::AuthFailedError.new("#{type} was refused", code: :auth_failed, status: 403)
        else
          Airplay::ProtocolError.new("#{type} answered #{response.status}",
                                     code: :protocol_error, status: response.status)
        end
      end
    end
  end
end
