require "airplay/browser"

module Airplay
  class Client
    def initialize(browser = Browser)
      @browser = browser.new
      @browser.browse
    end

    def nodes
      @browser.nodes
    end

    def active
      @_active ||= @browser.nodes.first
    end
  end
end
