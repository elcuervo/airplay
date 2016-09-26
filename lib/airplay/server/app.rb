require "cuba"
require "securerandom"

require "airplay/loggable"

module Airplay
  class Server
    class App < Cuba

      include Loggable

      settings[:assets] ||= Hash.new do |h, k|
        h[k] = SecureRandom.uuid
      end

      define do
        on root do
          body = []
          body << "Airplay Asset server v#{Airplay::VERSION}"

          res.write body.join("<br>")
        end

        on "assets/:uuid" do |uuid|
          log.debug("Device asked for asset #{uuid}.")
          log.debug("Currently this are the available assets #{settings[:assets]}")

          file = settings[:assets].key(uuid)
          dir = File.dirname(file)

          run Rack::File.new(dir)
        end
      end
    end
  end
end
