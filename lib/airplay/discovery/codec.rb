require "resolv"

require "airplay/errors"

module Airplay
  module Discovery
    SERVICE_TYPES = %w[_airplay._tcp.local. _raop._tcp.local.].freeze

    # Public: mDNS wire codec over the stdlib DNS message codec.
    class Codec
      Resource = Struct.new(:name, :ttl, :type, :data, keyword_init: true)
      Message = Struct.new(:id, :qr, :questions, :resources, keyword_init: true)

      class << self
        def query(name, id: 0)
          message = Resolv::DNS::Message.new(id)
          message.rd = 0
          message.add_question(Resolv::DNS::Name.create(name), Resolv::DNS::Resource::IN::PTR)
          message.encode
        end

        def decode(data)
          message = Resolv::DNS::Message.decode(data)
          if message.tc == 1
            raise Airplay::ProtocolError.new("truncated mDNS message", code: :truncated_mdns)
          end

          questions = []
          message.each_question do |name, type|
            questions << Resource.new(name: name.to_s, ttl: 0, type: type, data: nil)
          end

          resources = []
          message.each_resource do |name, ttl, resource|
            resources << Resource.new(name: name.to_s, ttl: ttl, type: resource.class, data: resource)
          end

          Message.new(id: message.id, qr: message.qr, questions: questions, resources: resources)
        rescue Airplay::Error
          raise
        rescue StandardError => error
          raise Airplay::ProtocolError.new(
            "malformed mDNS message: #{error.class}", code: :malformed_mdns
          )
        end

        def response(resources, id: 0)
          message = Resolv::DNS::Message.new(id)
          message.qr = 1
          message.aa = 1
          resources.each do |resource|
            message.add_answer(resource[:name], resource[:ttl], resource[:data])
          end
          message.encode
        end

        # Public: Splits TXT payloads on the first "=", preserving binary bytes.
        def txt(payloads)
          payloads.each_with_object({}) do |payload, map|
            next if payload.empty?

            key, value = payload.split("=", 2)
            map[key] = value || ""
          end
        end

        def encode_txt(map)
          map.map { |key, value| "#{key}=#{value}".b }
        end
      end
    end
  end
end
