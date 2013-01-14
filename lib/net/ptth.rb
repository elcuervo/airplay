require "uri"
require "net/http"
require "http-parser"
require "celluloid/io"

class Net::PTTH
  include Celluloid::IO

  def initialize(address, port = 80)
    @info = URI.parse(address)
    @socket = TCPSocket.new(@info.host, @info.port || port)
    @parser = HTTP::Parser.new
    puts "Connected"
  end

  def request(req, &block)
    packet = build(req)

    @socket.write(packet)

    response = @socket.readpartial(1024)
    @parser << response

    if @parser.http_status == 101
      while res = @socket.readpartial(1024)
        raw_headers = []
        headers = {}
        add_header = proc { |header| raw_headers << header }

        @parser.reset
        @parser.on_header_field &add_header
        @parser.on_header_value &add_header
        @parser.on_headers_complete do
          raw_headers.each_slice(2) do |key, value|
            headers[key] = value
          end
        end

        @parser.on_body { |body| block.call(body, headers) }

        @parser << res
      end
    end
  rescue EOFError => e
    puts e
  end

  private

  def build(req)
    req["Upgrade"]    ||= "PTTH/1.0"
    req["Connection"] ||= "Upgrade"

    package  = "#{req.method} #{req.path} HTTP/1.1\n"
    req.each_header do |header, value|
      package += "#{header.split("-").map(&:capitalize).join("-")}: #{value}\n"
    end

    package += "\n\r#{req.body}"
    package += "\n\r\n\r"
  end
end
