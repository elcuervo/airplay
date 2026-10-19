require "test_helper"
require "tmpdir"

class MediaServerTest < Airplay::TestCase
  class InstrumentedIO
    attr_reader :bytes

    def initialize(io)
      @io = io
      @bytes = 0
    end

    def seek(*arguments) = @io.seek(*arguments)

    def read(length)
      chunk = @io.read(length)
      return nil unless chunk

      @bytes += chunk.bytesize
      chunk
    end

    def close = @io.close
  end

  class CountingOpener
    attr_reader :io

    def open(path, mode)
      @io = InstrumentedIO.new(File.open(path, mode))
    end
  end

  def test_published_url_serves_the_file_and_is_opaque
    with_fixtures do |dir, video, other|
      Airplay.sync do
        server = Airplay::Media::Server.new(host: "127.0.0.1")
        url = server.publish(video)
        again = server.publish(video)
        different = server.publish(other)

        assert_equal url, again
        refute_equal url, different
        refute_includes url, "video.mov"
        refute_includes url, dir

        response = RangeClient.new(url).request(url.split("/").last)
        assert_equal 200, response.status
        assert_equal File.binread(video), response.body
        assert_equal "video/quicktime", response.headers["content-type"]
        assert_equal "4096", response.headers["content-length"]
        assert_equal "bytes", response.headers["accept-ranges"]
        server.stop
      end
    end
  end

  def test_closed_open_suffix_and_unsatisfiable_ranges
    with_fixtures do |_dir, video, _other|
      bytes = File.binread(video)

      Airplay.sync do
        server = Airplay::Media::Server.new(host: "127.0.0.1")
        url = server.publish(video)
        client = RangeClient.new(url)
        id = url.split("/").last

        closed = client.request(id, range: "bytes=100-199")
        assert_equal 206, closed.status
        assert_equal "bytes 100-199/4096", closed.headers["content-range"]
        assert_equal "100", closed.headers["content-length"]
        assert_equal bytes.byteslice(100, 100), closed.body

        open = client.request(id, range: "bytes=4000-")
        assert_equal 206, open.status
        assert_equal "bytes 4000-4095/4096", open.headers["content-range"]
        assert_equal bytes.byteslice(4000, 96), open.body

        suffix = client.request(id, range: "bytes=-100")
        assert_equal 206, suffix.status
        assert_equal "bytes 3996-4095/4096", suffix.headers["content-range"]
        assert_equal bytes.byteslice(3996, 100), suffix.body

        past = client.request(id, range: "bytes=5000-")
        assert_equal 416, past.status
        assert_equal "bytes */4096", past.headers["content-range"]
        assert_empty past.body

        whole = client.request(id, head: true)
        assert_equal 200, whole.status
        assert_equal "4096", whole.headers["content-length"]
        assert_empty whole.body

        ranged_head = client.request(id, range: "bytes=100-199", head: true)
        assert_equal 206, ranged_head.status
        assert_equal "bytes 100-199/4096", ranged_head.headers["content-range"]
        assert_empty ranged_head.body

        unknown = client.request("never-published")
        assert_equal 404, unknown.status
        assert_empty unknown.body
        server.stop
      end
    end
  end

  def test_a_range_on_an_empty_file_is_unsatisfiable
    Dir.mktmpdir do |dir|
      empty = File.join(dir, "empty.bin")
      File.binwrite(empty, "")

      Airplay.sync do
        server = Airplay::Media::Server.new(host: "127.0.0.1")
        url = server.publish(empty)
        response = RangeClient.new(url).request(url.split("/").last, range: "bytes=0-")

        assert_equal 416, response.status
        assert_equal "bytes */0", response.headers["content-range"]
        server.stop
      end
    end
  end

  def test_unknown_extensions_are_octet_stream
    with_fixtures do |_dir, _video, _other|
      Dir.mktmpdir do |dir|
        file = File.join(dir, "mystery.zzz")
        File.binwrite(file, "abc")

        Airplay.sync do
          server = Airplay::Media::Server.new(host: "127.0.0.1")
          url = server.publish(file)
          response = RangeClient.new(url).request(url.split("/").last)

          assert_equal "application/octet-stream", response.headers["content-type"]
          assert_equal "abc", response.body
          server.stop
        end
      end
    end
  end

  def test_a_range_reads_only_the_requested_bytes
    with_fixtures do |_dir, video, _other|
      opener = CountingOpener.new

      Airplay.sync do
        server = Airplay::Media::Server.new(host: "127.0.0.1", opener: opener)
        url = server.publish(video)
        RangeClient.new(url).request(url.split("/").last, range: "bytes=100-199")

        assert_equal 100, opener.io.bytes
        server.stop
      end
    end
  end

  def test_stopping_releases_the_port_and_unpublishes
    Dir.mktmpdir do |dir|
      file = File.join(dir, "a.mov")
      File.binwrite(file, "abc")

      Airplay.sync do
        server = Airplay::Media::Server.new(host: "127.0.0.1")
        url = server.publish(file)
        port = server.bound_port
        server.stop

        TCPServer.new("127.0.0.1", port).close
        assert_raises(SystemCallError) { RangeClient.new(url).request(url.split("/").last) }
      end
    end
  end

  def test_a_configured_port_is_used_verbatim
    Dir.mktmpdir do |dir|
      file = File.join(dir, "a.mov")
      File.binwrite(file, "abc")
      probe = TCPServer.new("127.0.0.1", 0)
      port = probe.addr[1]
      probe.close

      Airplay.sync do
        server = Airplay::Media::Server.new(host: "127.0.0.1", port: port)
        url = server.publish(file)

        assert_equal port, server.bound_port
        assert_includes url, ":#{port}/"
        server.stop
      end
    end
  end

  def test_publishing_requires_a_readable_regular_file
    Dir.mktmpdir do |dir|
      Airplay.sync do
        server = Airplay::Media::Server.new(host: "127.0.0.1")

        assert_raises(Airplay::PlaybackError) { server.publish(File.join(dir, "missing")) }
        assert_raises(Airplay::PlaybackError) { server.publish(dir) }
        assert_nil server.bound_port
        server.stop
      end
    end
  end

  def test_a_media_server_is_not_bound_until_a_file_is_published
    Airplay.sync do
      device = Airplay::Device.new(name: "Fake", host: "127.0.0.1", port: 7000)
      session = Airplay::Session.new(device)

      assert_nil session.media_server.bound_port
      session.close
    end
  end

  def test_a_slow_transfer_does_not_block_another_request
    Dir.mktmpdir do |dir|
      big = File.join(dir, "big.mov")
      File.binwrite(big, ("x" * (1024 * 1024)).b)

      Airplay.sync do
        server = Airplay::Media::Server.new(host: "127.0.0.1")
        url = server.publish(big)
        id = url.split("/").last

        stream = IO::Stream(Socket.tcp("127.0.0.1", server.bound_port))
        stream.write("GET /#{id} HTTP/1.1\r\nhost: x\r\nrange: bytes=0-1048575\r\nconnection: close\r\n\r\n",
                     flush: true)
        head = stream.read_until("\r\n\r\n")

        other = RangeClient.new(url).request(id, range: "bytes=0-9")
        assert_equal 206, other.status
        assert_equal "x" * 10, other.body

        body = stream.read_exactly(1024 * 1024)
        assert_equal 1024 * 1024, body.bytesize
        stream.close
        server.stop
      end
    end
  end

  private

  def with_fixtures
    Dir.mktmpdir do |dir|
      video = File.join(dir, "video.mov")
      other = File.join(dir, "other.mov")
      File.binwrite(video, (0...4096).map { |index| index % 256 }.pack("C*"))
      File.binwrite(other, (0...4096).map { |index| (index * 2) % 256 }.pack("C*"))
      yield dir, video, other
    end
  end
end
