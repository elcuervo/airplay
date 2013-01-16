require "cuba"
require "plist"

module Airplay::Protocol
  class App < Cuba
    class << self
      attr_accessor :pipeline
    end

    def pipe
      self.class.pipeline.mailbox
    end

    define do
      on "events" do
        plist = Plist.parse_xml(req.body)
        message = Message.create(
          type: :event,
          content: plist
        )

        pipe << message
      end
    end
  end
end
