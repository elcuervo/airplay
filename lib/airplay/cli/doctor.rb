module Airplay
  module CLI
    class Doctor
      DebugDevice = Struct.new(:node, :resolved) do
        def host
          info = Socket.getaddrinfo(resolved.target, nil, Socket::AF_INET)
          info[0][2]
        rescue SocketError
          target
        end
      end

      attr_accessor :devices

      def initialize
        @devices = []
      end

      def information
        find_devices!

        devices.each do |device|
          puts <<-EOS.gsub!(" "*12, "")
            Name: #{device.node.name}
            Host: #{device.host}
            Port: #{device.resolved.port}
            Full Name: #{device.node.fullname}
            Iface: #{device.node.interface_name}
            TXT: #{device.resolved.text_record}

          EOS
        end
      end

      private

      def find_devices!
        Timeout.timeout(5) do
          DNSSD.browse!(Airplay::Browser::SEARCH) do |node|
            try_resolving(node)
            break unless node.flags.more_coming?
          end
        end

        sleep 3
      end

      def try_resolving(node)
        Timeout.timeout(5) do
          DNSSD.resolve(node) do |resolved|
            devices << DebugDevice.new(node, resolved)

            break unless resolved.flags.more_coming?
          end
        end
      end
    end
  end
end
