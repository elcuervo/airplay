module Airplay::Protocol
  # Public: Handles the slideshows
  #
  class Slideshow
    def initialize
      @images = []
    end

    # Public: Lists all the slideshow features for the active device
    #
    # Returns the available themes hash
    #
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

    # Public: Adds images to the slideshow pool
    #
    #   images - An array of images to be added
    #
    def <<(*images)
      images.each { |image| @images << image }
    end

    # Public: Gets an images given a position on the list
    #
    #   position - The position on the list
    #
    def [](position)
      @images[position]
    end

    # Public: Pays the current slideshow
    #
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
  end
end
