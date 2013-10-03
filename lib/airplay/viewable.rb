require "forwardable"
require "airplay/protocol/viewer"

module Airplay
  module Viewable
    extend Forwardable

    def_delegators :viewer, :view, :transitions

    private

    def viewer
      @_viewer ||= Airplay::Protocol::Viewer.new(self)
    end
  end
end
