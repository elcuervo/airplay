module Airplay::Protocol
  class Slideshow
    def features
      @_features ||= begin
        response = Airplay.connection.get("/slideshow-features", {
          "Accept-Language" => "English"
        })

        Plist.parse_xml(response.body)["themes"]
      end
    end
  end
end
