require "airplay/structure"

module Airplay::Protocol
  # Public: Basic class to represent a message from an event callback
  #
  class Message < Structure.new(:type, :content)
  end
end
