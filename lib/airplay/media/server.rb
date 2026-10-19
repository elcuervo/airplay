require "async"
require "async/http"
require "securerandom"

require "airplay/errors"
require "airplay/media"

module Airplay
  module Media
    # Public: Serves published files to the receiver with HTTP byte ranges.
    class Server
      attr_reader :host, :port

      def initialize(host:, port: 0, opener: File)
        @host = host
        @port = port
        @opener = opener
        @files = {}
        @identifiers = {}
        @bound = nil
        @server = nil
        @task = nil
      end

      # Public: Publishes a readable regular file and returns its URL.
      def publish(path)
        path = File.expand_path(path)
        unless File.file?(path) && File.readable?(path)
          raise Airplay::PlaybackError.new("cannot publish #{path}", code: :playback_error)
        end

        identifier = @identifiers[path] ||= SecureRandom.uuid
        @files[identifier] = path
        start

        "http://#{host}:#{bound_port}/#{identifier}"
      end

      def stop
        @task&.stop
        @bound&.close
        @files.clear
        @identifiers.clear
        @bound = nil
        @server = nil
        @task = nil
        self
      end

      def bound_port
        @bound&.sockets&.first&.to_io&.local_address&.ip_port
      end

      def handle(request)
        path = @files[request.path.to_s.delete_prefix("/")]
        return response(404) unless path

        size = File.size(path)
        type = Airplay::Media.type_for(path)
        range = parse_range(request.headers["range"], size)
        head = request.method == "HEAD"
        base = { "content-type" => type, "accept-ranges" => "bytes" }

        if range == :unsatisfiable || range == :invalid
          response(416, base.merge("content-range" => "bytes */#{size}"))
        elsif range
          first, last = range
          response(206, base.merge("content-range" => "bytes #{first}-#{last}/#{size}"),
                   body_for(path, first, last - first + 1))
        else
          response(200, base, body_for(path, 0, size))
        end
      end

      private

      def start
        return self if @task

        endpoint = Async::HTTP::Endpoint.parse("http://0.0.0.0:#{@port}")
        @bound = endpoint.bound
        http = Async::HTTP::Endpoint.parse("http://0.0.0.0:#{bound_port}", @bound)
        @server = Async::HTTP::Server.new(method(:handle), http)
        @task = Async::Task.current.async do
          @bound.accept do |peer, address|
            @server.accept(peer, address)
          end
        end
        self
      end

      def response(status, headers = {}, body = nil)
        Protocol::HTTP::Response.new(nil, status, Protocol::HTTP::Headers[headers], body)
      end

      def body_for(path, offset, length)
        FileBody.new(@opener.open(path, "rb"), offset, length)
      end

      def parse_range(header, size)
        return nil if header.nil?

        match = header.to_s.match(/\Abytes=(\d*)-(\d*)\z/)
        return :invalid unless match
        return :invalid if size.zero?

        first = match[1]
        last = match[2]
        if first.empty?
          return :invalid if last.empty?

          count = last.to_i
          return :unsatisfiable if count.zero?

          start = [size - count, 0].max
          [start, size - 1]
        else
          start = first.to_i
          finish = last.empty? ? size - 1 : [last.to_i, size - 1].min
          return :unsatisfiable if start >= size || finish < start

          [start, finish]
        end
      end

      # Internal: Streams an explicit file slice and never reads past it.
      class FileBody
        include Enumerable

        CHUNK = 64 * 1024

        def initialize(io, offset, length)
          @io = io
          @offset = offset
          @length = length
        end

        def each
          while (chunk = read)
            yield chunk
          end
        end

        def join
          buffer = +"".b
          each { |chunk| buffer << chunk }
          buffer
        end

        def read
          unless @started
            @io.seek(@offset)
            @remaining = @length
            @started = true
          end
          return nil if @remaining.zero?

          chunk = @io.read([CHUNK, @remaining].min)
          return nil if chunk.nil? || chunk.empty?

          @remaining -= chunk.bytesize
          chunk
        end

        def length = @length
        def empty? = @length.zero?
        def ready? = false

        def close(*)
          @io.close
        rescue IOError
          nil
        end
      end
    end
  end
end
