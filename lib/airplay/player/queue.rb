require "securerandom"
require "socket"

require "airplay/errors"
require "airplay/media"
require "airplay/media/server"
require "airplay/playback/events"
require "airplay/playback/monitor"
require "airplay/playback/polling"
require "airplay/playback/state"
require "airplay/queue/client"
require "airplay/queue/now_playing"
require "airplay/queue/profile"

module Airplay
  module Player
    # Public: The modern play-queue route; every wire value comes from the profile.
    class Queue
      ROUTE = :queue
      PROPERTIES = {
        interested: ["isInterestedInDateRange", true],
        item_end: ["actionAtItemEnd", true]
      }.freeze

      attr_reader :session, :profile, :state, :monitor, :client, :item_id, :decision

      def initialize(session:, profile: nil, clock: Airplay.clock, now_playing: true,
                     media_host: nil, window: Playback::Monitor::DEFAULT_WINDOW,
                     decision: nil)
        @session = session
        @profile = profile || Airplay::Queue::Profile.select(session.capabilities&.srcvers)
        @clock = clock
        @state = Playback::State.new
        @events = Playback::Events.new(state: @state, clock: clock)
        @polling = Playback::Polling.new(state: @state, session: session, clock: clock)
        @monitor = Playback::Monitor.new(state: @state, events: @events, polling: @polling,
                                         clock: clock, window: window)
        @session.on_event { |event| @monitor.handle_event(event) }
        @client = Airplay::Queue::Client.new(session: session, profile: @profile,
                                    stream_id: -> { session.stream_id }, clock: clock)
        @now_playing = Airplay::Queue::NowPlaying.new(client: @client, clock: clock, enabled: now_playing)
        @media_host = media_host
        @media_server = nil
        @stream_id = nil
        @item_id = nil
        @items = []
        @index = -1
        @decision = decision
      end

      def now_playing
        @now_playing
      end

      def media_server
        @media_server ||= Airplay::Media::Server.new(host: @media_host)
      end

      # Public: Registers the URL control stream once, before any queue command.
      def register!
        return @stream_id if @stream_id

        @session.register_control_stream(profile: @profile)
        @stream_id = @session.stream_id
      end

      # Public: Starts playback on the receiver's queue and begins the startup window.
      def play(media, position: 0.0)
        register!
        url = resolved_url(media)
        @item_id = SecureRandom.uuid
        @client.insert(uuid: @item_id, url: url, position: position)
        @client.property(*PROPERTIES[:interested])
        @client.property(*PROPERTIES[:item_end]) if @profile.action_at_item_end
        @client.rate(1.0)
        @items << { media: url, uuid: @item_id }
        @index = @items.length - 1
        @monitor.start
        @item_id
      end

      def add(media)
        register!
        url = resolved_url(media)
        uuid = SecureRandom.uuid
        @client.insert(uuid: uuid, url: url, retryable: false)
        @items << { media: url, uuid: uuid }
        uuid
      end

      def remove(uuid)
        register!
        @client.remove(uuid: uuid)
      end

      def pause
        register!
        @client.rate(0.0)
        @now_playing.pause
      end

      def resume
        register!
        @client.rate(1.0)
        @now_playing.resume
      end

      # Public: Stop is a rate-zero command followed by removing the current item.
      def stop
        register!
        @client.rate(0.0)
        @client.remove(uuid: @item_id) if @item_id
        @now_playing.stop
        @item_id = nil
      end

      def seek(position)
        register!
        raise Airplay::PlaybackError.new("nothing is playing", code: :playback_error) unless @item_id

        @client.seek(uuid: @item_id, position: position)
        @now_playing.seek(elapsed: position)
      end

      def rate(value)
        register!
        @client.rate(value)
        @now_playing.correct(rate: value)
      end

      def next
        navigate(1)
      end

      def previous
        navigate(-1)
      end

      # Public: Requests a state snapshot and correlates its answer by identifier.
      def request_snapshot
        register!
        identifier = SecureRandom.uuid
        @events.expect(identifier)
        @client.snapshot(request_id: identifier)
        identifier
      end

      def wait(require_start: true, &block)
        @state.on_change(&block) if block
        @monitor.wait(require_start: require_start)
      end

      def close
        @media_server&.stop
        @media_server = nil
        @session.close
      end

      private

      # Internal: Selects an already queued item, inserting it first when unknown.
      def navigate(offset)
        register!
        return nil if @items.empty?

        @index = (@index + offset) % @items.length
        entry = @items[@index]
        unless entry[:uuid]
          entry[:uuid] = SecureRandom.uuid
          @client.insert(uuid: entry[:uuid], url: entry[:media], retryable: false)
        end
        @client.select(uuid: entry[:uuid])
        @item_id = entry[:uuid]
        @item_id
      end

      # Internal: Remote media is handed unchanged; a local file is published.
      def resolved_url(media)
        url = media.is_a?(Airplay::Media::Media) ? (media.url || media.source) : media.to_s
        return url if url.match?(%r{\Ahttps?://})

        publish(url)
      end

      def publish(path)
        unless File.file?(path)
          raise Airplay::PlaybackError.new("cannot play #{path}", code: :playback_error)
        end
        if @media_host.nil?
          raise Airplay::PlaybackError.new(
            "the media server can only be addressed on a loopback interface",
            code: :unusable_media_address
          )
        end

        media_server.publish(path)
      end
    end
  end
end
