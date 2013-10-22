require "cuba"

module Airplay
  class Server
    class App < Cuba
      settings[:assets] ||= Hash.new do |h, k|
        h[k] = UUID.generate
      end

      define do
        on "assets/:uuid" do |uuid|
          run Rack::File.new(settings[:assets].key(uuid))
        end
      end
    end
  end
end
