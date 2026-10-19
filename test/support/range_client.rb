require "io/stream"
require "socket"
require "uri"

# Public: Minimal HTTP client for the media server's range contract.
class RangeClient
  Result = Struct.new(:status, :headers, :body, keyword_init: true)

  class << self
    def parse(raw)
      head, _, body = raw.partition("\r\n\r\n")
      lines = head.split("\r\n")
      status = lines.shift.to_s.split(" ")[1].to_i
      headers = lines.each_with_object({}) do |line, hash|
        name, value = line.split(":", 2)
        hash[name.to_s.downcase] = value.to_s.strip
      end
      length = headers["content-length"].to_i

      Result.new(status: status, headers: headers, body: body.byteslice(0, length))
    end
  end

  def initialize(url)
    @uri = URI(url)
  end

  def request(identifier, range: nil, head: false)
    stream = IO::Stream(Socket.tcp(@uri.host, @uri.port))
    method = head ? "HEAD" : "GET"
    lines = ["host: #{@uri.host}", "connection: close"]
    lines << "range: #{range}" if range
    stream.write("#{method} /#{identifier} HTTP/1.1\r\n#{lines.join("\r\n")}\r\n\r\n", flush: true)

    head_raw = stream.read_until("\r\n\r\n", chomp: false)
    length = head_raw[/content-length:\s*(\d+)/i, 1].to_i
    body = !head && length.positive? ? stream.read_exactly(length) : "".b
    stream.close

    self.class.parse(head_raw + body)
  end
end
