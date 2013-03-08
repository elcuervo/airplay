require "cuba"
require "base64"
require "cfpropertylist"

module Airplay::Protocol
  # Public: The app to be mounted on the reverse connection
  #
  class App < Cuba
    class << self
      attr_accessor :pipeline
    end

    def pipe
      self.class.pipeline.mailbox
    end

    define do
      on post, "event" do
        plist = CFPropertyList::List.new(data: req.body.read)
        native_plist = CFPropertyList.native_types(plist.value)

        message = Message.create(
          type:    :event,
          content: native_plist
        )

        pipe << message
      end

      on "slideshows/1/assets/:id" do |id|
        image = File.read("test/fixtures/files/logo.png")
        image.force_encoding("BINARY")

        data = {
          data: CFPropertyList::Blob.new(image),
          info: {
            id: 1,
            key: id
          }
        }

        res["Content-Type"] = "application/x-apple-binary-plist"

        plist = CFPropertyList::List.new
        plist.value = CFPropertyList.guess(data)
        binary_plist = plist.to_str

        res.write binary_plist
      end
    end
  end
end
