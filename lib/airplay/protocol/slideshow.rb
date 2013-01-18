require "uuid"

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

        Plist.parse_xml(response.body)["themes"]
      end
    end

    def <<(*images)
      images.each { |image| @images << image }
    end

    def [](position)
      @images[position]
    end

    def stop
      Airplay.connection.post("stop")
    end

    def play

      content = {
        settings: {
          slideDuration: 3,
          theme: "Dissolve"
        },
        state: "playing"
      }

      Airplay.connection.reverse.callbacks[:event] << proc do |response|
        if response["category"] == "slideshow"
          puts response
        end
      end

      response = Airplay.connection.put("/slideshows/1", Plist::Emit.dump(content), {
        "Content-Type" => "text/x-apple-plist+xml"
      })

      @reverse ||= Airplay::Protocol::Reverse.new("http://#{Airplay.active.address}", "slideshow")
      @reverse.async.connect

      response.code == "200"
    end

    def stop
      Airplay.connection.post("/stop")
    end
  end
end
