require "airplay/discovery/browser"

module Airplay
  module Discovery
    # Public: Enumerable view over the current discovery records.
    class Devices
      include Enumerable

      def initialize(browser: Browser.new, records: [])
        @browser = browser
        @records = records
      end

      def each
        return enum_for(:each) unless block_given?
        browse if @records.empty? && Airplay.configuration.autodiscover
        @records.each { |record| yield record }
      end

      def browse(window: nil, force: false)
        result = @browser.browse(window: window, force: force)
        @records = result.records
        result
      end

      def [](name)
        find { |record| record.display_name == name || record.name == name }
      end

      def find_by_identifier(value)
        find { |record| record.identifier == value || record.capabilities.device_id == value }
      end

      def find_by_address(value)
        find { |record| record.addresses.any? { |address| address.ip.to_s == value } }
      end

      def reset!
        @records = []
        @browser.cache.clear
      end
    end
  end
end
