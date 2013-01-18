require "cuba"
require "base64"
require "cfpropertylist"
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
      on post, "event" do
        plist = Plist.parse_xml(req.body)
        message = Message.create(
          type: :event,
          content: plist
        )

        pipe << message

        res.write ""
      end

      on "slideshows/1/assets/:id" do |id|
        image = File.read("test/fixtures/files/logo.jpeg")
        image.force_encoding('BINARY')

        data = {
          data: CFPropertyList::Blob.new(image),
          info: { id: 1, key: 1 }
        }

        res["Content-Type"] = "application/x-apple-binary-plist"

        plist = CFPropertyList::List.new
        plist.value = CFPropertyList.guess(data)
        binary_plist = plist.to_str

        res["Content-Length"] = 10
        res.write binary_plist
      end

      on default do
        require 'ruby-debug';debugger;1
      end
    end
  end
end
