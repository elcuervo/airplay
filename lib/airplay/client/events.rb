require "celluloid"
require "nokogiri"
require "net/ptth"
require "net/http"

module Airplay
  class Client
    class Events
      include Celluloid

      attr_accessor :callback

      def initialize(server)
        @ptth = Net::PTTH.new(server)
      end

      def disconnect
        @ptth.close
      end

      def connect
        request = Net::HTTP::Post.new("/reverse")
        request["X-Apple-Purpose"] = "event"

        @ptth.request(request) do |incoming_request|
          plist = Plist.parse_xml(incoming_request.body.read)

          (@callback || Proc.new {}).call(plist)
        end
      end
    end
  end
end
