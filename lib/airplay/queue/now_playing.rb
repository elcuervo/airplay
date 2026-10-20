require "async"
require "async/semaphore"
require "digest"
require "securerandom"

require "airplay/errors"
require "airplay/plist"
require "airplay/status"

module Airplay
  module Queue
    # Public: MediaRemote now-playing pushes, change-driven and never fatal.
    class NowPlaying
      COMMANDS = {
        info: "updateNowPlayingInfo",
        supported: "updateSupportedCommands",
        state: "updatePlaybackState",
        client: "updatePlaybackClient"
      }.freeze
      MERGE_FULL = "replace"
      MERGE_UPDATE = "update"
      CLIENT = { "bundleIdentifier" => "com.apple.airplay.sender", "name" => "airplay" }.freeze
      DEFAULT_SUPPORTED = %w[play pause stop next previous seek].freeze

      attr_reader :client, :item_id, :pushes, :failures

      def initialize(client:, clock: Airplay.clock, enabled: true)
        @client = client
        @clock = clock
        @enabled = enabled
        @item_id = nil
        @info = {}
        @elapsed = nil
        @rate = nil
        @duration = nil
        @artwork = nil
        @artwork_mime = nil
        @state = nil
        @supported = nil
        @full_only = false
        @last_signatures = {}
        @pushing = false
        @pushes = []
        @failures = []
        @lock = Async::Semaphore.new(1)
      end

      def enabled?
        @enabled
      end

      def active?
        !@item_id.nil?
      end

      # Public: Starts a new item: new identity, fresh artwork, the initial sequence.
      def item(uuid: nil, **metadata)
        @item_id = uuid || SecureRandom.uuid
        @info = metadata
        @duration = metadata[:duration]
        @artwork = metadata[:artwork]
        @artwork_mime = metadata[:artwork_mime]
        @elapsed = metadata[:elapsed] || 0.0
        @rate = metadata[:rate] || 1.0
        @last_signatures = {}
        push_info(full: true)
        push_supported(DEFAULT_SUPPORTED)
        push_state(:playing)
        push_client
        self
      end

      # Public: Updates metadata for the current item; identity and artwork persist.
      def update(**metadata)
        return nil unless active?

        @info = @info.merge(metadata)
        @duration = metadata.fetch(:duration, @duration)
        @elapsed = metadata.fetch(:elapsed, @elapsed)
        @rate = metadata.fetch(:rate, @rate)
        push_info(full: true)
      end

      # Public: Reports progress for the current item without changing identity.
      def progress(elapsed:, rate: nil)
        return nil unless active?

        @elapsed = elapsed
        @rate = rate unless rate.nil?
        push_info(full: true)
      end

      # Public: A timeline-only correction in the update form.
      def correct(elapsed: nil, rate: nil)
        return nil unless active?

        @elapsed = elapsed unless elapsed.nil?
        @rate = rate unless rate.nil?
        push_info(full: false)
      end

      def seek(elapsed:)
        return nil unless active?

        correct(elapsed: elapsed)
      end

      def pause
        return nil unless active?

        correct(rate: 0.0)
        push_state(:paused)
      end

      def resume
        return nil unless active?

        correct(rate: 1.0)
        push_state(:playing)
      end

      # Public: Pushes state only, with no timeline correction.
      def stop
        return nil unless active?

        push_state(:stopped)
      end

      def state(value)
        @state = value
        push_state(value)
      end

      def supported(commands)
        return nil if @supported == commands

        push_supported(commands)
      end

      private

      def push_info(full:)
        return nil unless active?

        full ||= @full_only
        now_playing = timeline
        if full
          now_playing["text"] = @info.slice(:title, :artist, :album).compact.transform_keys(&:to_s)
          attach_artwork(now_playing)
        end
        payload = envelope(COMMANDS[:info],
                           { "nowPlayingInfo" => now_playing,
                             "mergePolicy" => full ? MERGE_FULL : MERGE_UPDATE })
        push(payload, update_form: !full)
      end

      def timeline
        fields = { "uuid" => @item_id, "elapsed" => @elapsed, "rate" => @rate,
                   "timestamp" => timestamp }
        fields["duration"] = @duration unless @duration.nil?
        fields.compact
      end

      def attach_artwork(fields)
        return if @artwork.nil?

        fields["artwork"] = Airplay::Plist::Data.new(@artwork.to_s.b)
        fields["artworkMimeType"] = @artwork_mime if @artwork_mime
        fields["artworkIdentifier"] = Digest::SHA256.hexdigest(@artwork.to_s.b)
      end

      def push_supported(commands)
        @supported = Array(commands)
        push(envelope(COMMANDS[:supported], { "commands" => @supported }))
      end

      def push_state(value)
        @state = value
        push(envelope(COMMANDS[:state], { "state" => value.to_s }))
      end

      def push_client
        push(envelope(COMMANDS[:client], CLIENT.dup))
      end

      def envelope(type, params)
        { "type" => type, "params" => params }
      end

      def timestamp
        Process.clock_gettime(Process::CLOCK_REALTIME).then { |at| Time.at(at).utc }
      end

      # Internal: Serializes pushes so two concurrent changes never interleave.
      def push(payload, update_form: false)
        return nil unless @enabled

        signature = signature_for(payload)
        return nil if signature == @last_signatures[payload["type"]]

        deliver = lambda do
          @pushes << payload
          @last_signatures[payload["type"]] = signature
          response = @client.deliver(payload)
          record_failure(response, update_form)
        rescue Airplay::Error => error
          @failures << { status: error.status, error: error.code, update_form: update_form }
          Airplay::Status.emit("now_playing.rejected", status: error.status, code: error.code)
          nil
        end
        if Async::Task.current?
          @lock.acquire { deliver.call }
        else
          deliver.call
        end
        payload
      end

      def signature_for(payload)
        Marshal.dump(normalize(payload))
      end

      def normalize(value)
        case value
        when Hash
          value.reject { |key, _| key.to_s == "timestamp" }
               .keys.sort_by(&:to_s)
               .to_h { |key| [key.to_s, normalize(value[key])] }
        when Array then value.map { |item| normalize(item) }
        when Airplay::Plist::Data then "data:#{Digest::SHA256.hexdigest(value.bytes)}"
        when Time then "time"
        else value
        end
      end

      def record_failure(response, update_form)
        return if response.status.between?(200, 299)

        @failures << { status: response.status, update_form: update_form }
        Airplay::Status.emit("now_playing.rejected", status: response.status,
                                                    update_form: update_form)
        @full_only = true if update_form && (400..499).cover?(response.status)
        nil
      end
    end
  end
end
