require "net/http"

module Airplay
  # Public: The class that handles all the outgoing basic HTTP connections
  #
  class Connection
    Response = Struct.new(:parser, :body) do
      def code
        parser.status_code
      end
    end
  end
end
