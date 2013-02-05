require "dnssd"
require "airplay/nodes"

module Airplay
  # Public: Browser class to find Airplay-enabled devices in the network
  #
  class Browser
    SEARCH = "_airplay._tcp."

    # Public: Browses in the search of devices and adds them to the nodes
    #
    def browse
      timeout(3) do
        DNSSD.browse!(SEARCH) do |node|
          resolver = DNSSD::Service.new

          resolver.resolve(node) do |resolved|
            info = Socket.getaddrinfo(resolved.target, nil, Socket::AF_INET)
            ip = info[0][2]

            airplay_node = Node.create(
              name:     node.name,
              address: "#{ip}:#{resolved.port}",
              domain:   node.domain
            )
            airplay_node.parse_info(resolved.text_record)

            nodes << airplay_node

            break unless resolved.flags.more_coming?
          end
          break unless node.flags.more_coming?
        end
      end
    end

    # Public: Access to the node list
    #
    def nodes
      @_nodes ||= Nodes.new
    end
  end
end
