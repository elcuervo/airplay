require "async"
require "ipaddr"
require "socket"

module Airplay
  # Public: Resolves device names without stalling the reactor.
  class Resolver
    def resolve(host, port)
      return [[host, port]] if ip_literal?(host)
      Addrinfo.getaddrinfo(host, port, nil, :STREAM).map do |address|
        [address.ip_address, address.ip_port]
      end
    end

    # Public: Runs #resolve in a thread and wakes the waiting task on completion.
    def resolve_without_blocking(host, port)
      return [[host, port]] if ip_literal?(host)

      result = nil
      error = nil
      notification = Async::Notification.new

      Thread.new do
        begin
          result = resolve(host, port)
        rescue Exception => exception # rubocop:disable Lint/RescueException
          error = exception
        ensure
          notification.signal
        end
      end

      notification.wait
      raise error if error
      result
    end

    private

    def ip_literal?(host)
      IPAddr.new(host)
      true
    rescue IPAddr::InvalidAddressError
      false
    end
  end
end
