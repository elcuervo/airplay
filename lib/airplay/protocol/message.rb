require "airplay/structure"

module Airplay::Protocol
  class Message < Structure.new(:type, :content)
  end
end
