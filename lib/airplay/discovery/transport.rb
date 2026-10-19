require "ipaddr"
require "socket"

require "airplay/errors"

module Airplay
  module Discovery
    # Public: Multicast datagram sockets, one per interface and family.
    class Transport
      GROUP_V4 = "224.0.0.251"
      GROUP_V6 = "ff02::fb"

      Endpoint = Struct.new(:io, :family, :interface, :index, keyword_init: true)

      class << self
        def open(port:, interfaces: nil, families: [:ipv4])
          addrs = Socket.getifaddrs.select { |ifaddr| ifaddr.addr&.ip? }

          selected =
            if interfaces
              names = interfaces.map(&:to_s)
              found = addrs.select { |ifaddr| names.include?(ifaddr.name) }
              if found.empty?
                raise Airplay::TransportError.new(
                  "interface not found: #{names.join(", ")}", code: :interface_unavailable
                )
              end
              found
            else
              addrs.reject { |ifaddr| ifaddr.name.start_with?("utun", "awdl", "llw") }
                   .uniq { |ifaddr| [ifaddr.name, ifaddr.addr.ipv6?] }
            end

          sockets = selected.filter_map do |ifaddr|
            family = ifaddr.addr.ipv6? ? :ipv6 : :ipv4
            next unless families.include?(family)

            build(ifaddr, family, port)
          end

          if sockets.empty? && interfaces
            raise Airplay::TransportError.new(
              "no usable socket for #{interfaces.join(", ")}", code: :interface_unavailable
            )
          end

          sockets
        end

        def send(socket, data, port)
          group = socket.family == :ipv4 ? GROUP_V4 : GROUP_V6
          socket.io.send(data, 0, Addrinfo.udp(group, port))
        end

        def receive(socket, timeout)
          return nil unless socket.io.wait_readable(timeout)

          data, source = socket.io.recvfrom_nonblock(65_535, exception: false)
          return nil if data == :wait_readable

          [data, source]
        end

        private

        def build(ifaddr, family, port)
          io = Socket.new(
            family == :ipv4 ? Socket::AF_INET : Socket::AF_INET6,
            Socket::SOCK_DGRAM, 0
          )
          io.setsockopt(Socket::SOL_SOCKET, Socket::SO_REUSEADDR, true)
          io.setsockopt(Socket::SOL_SOCKET, Socket::SO_REUSEPORT, true)

          if family == :ipv4
            io.bind(Addrinfo.udp("0.0.0.0", port))
            membership = IPAddr.new(GROUP_V4).hton + IPAddr.new(ifaddr.addr.ip_address).hton
            io.setsockopt(Socket::IPPROTO_IP, Socket::IP_ADD_MEMBERSHIP, membership)
            io.setsockopt(Socket::IPPROTO_IP, Socket::IP_MULTICAST_IF,
                          IPAddr.new(ifaddr.addr.ip_address).hton)
            io.setsockopt(Socket::IPPROTO_IP, Socket::IP_MULTICAST_LOOP, 1)
          else
            io.setsockopt(Socket::IPPROTO_IPV6, Socket::IPV6_V6ONLY, 1)
            io.bind(Addrinfo.udp("::", port))
            membership = IPAddr.new(GROUP_V6).hton + [ifaddr.ifindex].pack("i")
            io.setsockopt(Socket::IPPROTO_IPV6, Socket::IPV6_JOIN_GROUP, membership)
            io.setsockopt(Socket::IPPROTO_IPV6, Socket::IPV6_MULTICAST_IF,
                          [ifaddr.ifindex].pack("i"))
            io.setsockopt(Socket::IPPROTO_IPV6, Socket::IPV6_MULTICAST_LOOP, 1)
          end

          Endpoint.new(io: io, family: family, interface: ifaddr.name, index: ifaddr.ifindex)
        rescue SystemCallError, SocketError
          io&.close
          nil
        end
      end
    end
  end
end
