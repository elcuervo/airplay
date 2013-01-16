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
          plist = Nokogiri::XML(incoming_request.body.read)
          response = {}
          plist.search("dict/*").each_slice(2) do |key, value|
            response[key.text] = value.text
          end

          (@callback || Proc.new {}).call(response)
        end
      end
    end
  end
end
