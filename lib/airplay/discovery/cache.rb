module Airplay
  module Discovery
    # Public: TTL-aware record cache.
    class Cache
      Entry = Struct.new(:record, :expires_at)

      def initialize(clock: Airplay.clock)
        @clock = clock
        @entries = {}
      end

      def put(record)
        if record.ttl.to_i <= 0
          remove(record.name)
        else
          @entries[record.name] = Entry.new(record, @clock.now + record.ttl)
        end
      end

      def remove(name)
        @entries.delete(name)
      end

      def records
        now = @clock.now
        @entries.delete_if { |_name, entry| entry.expires_at <= now }
        @entries.values.map(&:record)
      end

      def fresh?
        !records.empty?
      end

      def empty?
        records.empty?
      end

      def clear
        @entries.clear
      end
    end
  end
end
