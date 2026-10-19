require "async"
require "io/stream"
require "socket"

require "airplay/errors"
require "airplay/pairing/frame"

module Airplay
  module Pairing
    # Public: One control connection: plaintext HTTP until the channel keys are
    # installed, then AEAD-framed HTTP on the same socket.
    class Connection
      Response = Struct.new(:status, :headers, :body, keyword_init: true)

      attr_reader :host, :port, :timeout

      def initialize(host:, port:, timeout: 10)
        @host = host
        @port = port
        @timeout = timeout
        @io = nil
        @reader = nil
        @writer = nil
      end

      def open
        @io = IO::Stream(Socket.tcp(@host, @port))
        self
      rescue SystemCallError => error
        raise Airplay::TransportError.new("cannot connect to #{host}:#{port}: #{error.message}",
                                          code: :connect_failed)
      end

      def close
        @io&.close
        @io = nil
      end

      def encrypted?
        !@writer.nil?
      end

      # Public: [read counter, write counter] for the installed frame codecs.
      def counters
        [@reader&.counter, @writer&.counter]
      end

      # Public: Installs the frame keys; every later request is framed.
      def encrypt!(write_key, read_key)
        @writer = Frame.new(write_key)
        @reader = Frame.new(read_key)
        self
      end

      # Public: Sends one request, framed or plaintext depending on the state.
      def request(method, path, body: nil, headers: {})
        raise Airplay::SessionClosedError.new("connection is closed", code: :session_closed) unless @io

        Async::Task.current.with_timeout(timeout) do
          payload = serialize(method, path, body, headers)

          if encrypted?
            @io.write(@writer.encrypt(payload), flush: true)
            read_framed
          else
            @io.write(payload, flush: true)
            read_plain
          end
        end
      rescue Async::TimeoutError
        close
        raise Airplay::TimeoutError.new("request timed out after #{timeout}s", code: :timeout)
      rescue Airplay::Error
        close
        raise
      rescue EOFError, SystemCallError, IOError => error
        close
        raise Airplay::TransportError.new("connection lost: #{error.message}", code: :connect_failed)
      end

      private

      def serialize(method, path, body, headers)
        body = body.to_s.b
        fields = { "host" => "#{host}:#{port}", "content-length" => body.bytesize.to_s }
        headers.each { |name, value| fields[name.to_s.downcase] = value.to_s }
        lines = ["#{method} #{path} HTTP/1.1"] + fields.map { |name, value| "#{name}: #{value}" }

        (lines.join("\r\n") + "\r\n\r\n").b + body
      end

      def read_plain
        status = read_line
        raise EOFError, "connection closed before the response" unless status

        headers = read_headers
        body = headers["content-length"] ? @io.read_exactly(headers["content-length"].to_i) : "".b

        Response.new(status: status.split(" ")[1].to_i, headers: headers, body: body)
      end

      def read_headers
        headers = {}
        while (line = read_line) && !line.empty?
          name, value = line.split(":", 2)
          headers[name.to_s.downcase] = value.to_s.strip
        end
        headers
      end

      def read_line
        @io.read_until("\r\n")
      end

      def read_framed
        header = @io.read_exactly(2)
        length = header.unpack1("v")
        if length > Frame::MAX_LENGTH
          raise Airplay::TransportError.new("oversized frame length #{length}", code: :connect_failed)
        end

        parse_response(@reader.decrypt(header + @io.read_exactly(length + Frame::TAG_LENGTH)))
      end

      def parse_response(bytes)
        head, _, body = bytes.to_s.b.partition("\r\n\r\n")
        lines = head.split("\r\n")
        status = lines.shift.to_s.split(" ")[1].to_i
        headers = lines.each_with_object({}) do |line, hash|
          name, value = line.split(":", 2)
          hash[name.to_s.downcase] = value.to_s.strip
        end

        Response.new(status: status, headers: headers, body: body)
      end
    end
  end
end
