module Airplay::Protocol
  class Slideshow
    def initialize
      @images = []
    end

    def features
      @_features ||= begin
        response = Airplay.connection.get("/slideshow-features", {
          "Accept-Language" => "English"
        })

        plist = CFPropertyList::List.new(data: response.body)
        native_plist = CFPropertyList.native_types(plist.value)

        native_plist["themes"]
      end
    end

    def <<(*images)
      images.each { |image| @images << image }
    end

    def [](position)
      @images[position]
    end

    def play
      @reverse = Airplay::Protocol::Reverse.new(Airplay.active, "slideshow")
      @reverse.async.connect

      content = {
        settings: {
          slideDuration: 3,
          theme: "Dissolve".upcase
        },
        state: "playing"
      }

      plist = CFPropertyList::List.new
      plist.value = CFPropertyList.guess(content)

      response = Airplay.connection.async.put("/slideshows/1", plist.to_str(2), {
        "Content-Type" => "text/x-apple-plist+xml"
      })

    end

    def stop
      Airplay.connection.post("/stop")
    end
  end
end
