require "celluloid"
require "dnssd"

class Struct
  def self.create(hash)
    new(*members.map { |member| hash[member.to_sym] })
  end
end

module Airplay
  class Player
  end

  class Browser
    SEARCH = "_airplay._tcp."

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

    def nodes
      @_nodes ||= Nodes.new
    end
  end

  class Nodes
    include Enumerable

    def initialize
      @items = []
    end

    def each(&block)
      @items.each(&block)
    end

    def <<(value)
      @items << value
    end

    def size
      @items.size
    end
  end

  class Node < Struct.new(:name, :address, :domain)
    class Info < Struct.new(:deviceid, :features, :model, :srcvers); end

    class Features < Struct.new(:video, :photo, :video_fair_play,
                                :video_volume_control, :video_http_live_stream,
                                :slideshow, :screen, :screen_rotate, :audio,
                                :audio_redundant, :FPSAPv2pt5_AES_GCM,
                                :photo_caching)
      def self.load(features)
        create(
          video:                  0 < (features & ( 1 <<  0 )),
          photo:                  0 < (features & ( 1 <<  1 )),
          video_fair_play:        0 < (features & ( 1 <<  2 )),
          video_volume_control:   0 < (features & ( 1 <<  3 )),
          video_http_live_stream: 0 < (features & ( 1 <<  4 )),
          slideshow:              0 < (features & ( 1 <<  5 )),
          screen:                 0 < (features & ( 1 <<  7 )),
          screen_rotate:          0 < (features & ( 1 <<  8 )),
          audio:                  0 < (features & ( 1 <<  9 )),
          audio_redundant:        0 < (features & ( 1 << 11 )),
          FPSAPv2pt5_AES_GCM:     0 < (features & ( 1 << 12 )),
          photo_caching:          0 < (features & ( 1 << 13 ))
        )
      end
    end

    attr_accessor :features, :ip, :port, :info, :features

    def initialize(*)
      super
      parse_address
    end

    def parse_info(info)
      @info = Info.create(info)
      @features = Features.load(info.fetch("features", "0").hex)
    end

    private

    def parse_address
      @ip, port = address.split(":")
      @port = port.to_i
    end

  end

  class Client
    def initialize(browser = Browser)
      @browser = browser.new
      @browser.browse
    end

    def nodes
      @browser.nodes
    end
  end

  class << self
    def nodes
      client.nodes
    end

    private

    def client
      @_client ||= Client.new
    end
  end
end
