require "airplay/errors"

module Airplay
  # Public: A device the session can reach.
  class Device
    MissingAttributes = Class.new(KeyError)

    attr_reader :name, :host, :port, :model, :password

    # shortcut: host:port strings only; structured service records replace this in mdns-discovery.
    def initialize(name: nil, address: nil, host: nil, port: nil, model: nil, password: nil)
      if address
        parsed_host, parsed_port = address.split(":", 2)
        host ||= parsed_host
        port ||= parsed_port
      end

      raise MissingAttributes, "a name and an address are mandatory" unless name && host

      @name = name
      @host = host
      @port = Integer(port || 7000)
      @model = model
      @password = password
    end

    def address
      "#{host}:#{port}"
    end

    alias ip host

    def password?
      !password.nil? && !password.empty?
    end

    def with_password(value)
      self.class.new(name: name, host: host, port: port, model: model, password: value)
    end

    def ==(other)
      other.is_a?(Device) &&
        other.name == name && other.host == host && other.port == port
    end

    def to_s
      name
    end
  end
end
