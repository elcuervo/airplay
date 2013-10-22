require "forwardable"
require "airplay/viewer"

module Airplay
  module Viewable
    extend Forwardable

    def_delegators :viewer, :view, :transitions

    private

    def viewer
      @_viewer ||= Airplay::Viewer.new(self)
    end
  end
end
