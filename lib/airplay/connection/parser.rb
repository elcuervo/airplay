require "http/parser"

module Airplay
  # Public: The class that handles all the outgoing basic HTTP connections
  #
  class Connection
    class Parser
      attr_reader :headers, :chunk, :finished
      attr_accessor :on_finish

      # Public: Contructor
      #
      def initialize
        @parser = Http::Parser.new(self)

        reset
      end

      # Public: Adds data to be parsed.
      #
      #   data: string to be parsed
      #
      def add(data)
        @parser << data
      end
      alias_method :<<, :add

      # Public: Check for an upgrade header in the parsed string
      #
      def upgrade?
        @parser.upgrade?
      end

      # Public: Gets the http method parsed
      #
      def http_method
        @parser.http_method
      end

      # Public: Gets the http version parsed
      #
      def http_version
        @parser.http_version
      end

      # Public: Gets the status code parsed
      #
      def status_code
        @parser.status_code
      end

      # Public: Gets the url parsed
      #
      def url
        @parser.request_url
      end

      # Public: Internal flag access to know when parsing ended
      #
      def finished?
        !!@finished
      end

      def finished!
        @finished = true
      end

      # Public: Resets the parser internal flags
      #
      def reset
        @finished = false
        @headers  = nil
        @chunk    = ""
      end

      # Public: Access the body of the string being parsed
      #
      def body
        @chunk
      end

      def body=(chunk)
        @chunk << chunk
      end

      # Protected: Sets the headers when the parser completes.
      #
      def on_headers_complete(headers)
        @headers = headers
      end

      def on_message_begin
        reset
      end

      # Protected: Flags the parsing as ended
      #
      def on_message_complete
        @on_finish.call
        finished!
      end
    end
  end
end
