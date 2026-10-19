require "test_helper"

class RangeClientTest < Minitest::Test
  def test_parses_whole_and_partial_responses
    whole = RangeClient.parse("HTTP/1.1 200 OK\r\ncontent-length: 3\r\naccept-ranges: bytes\r\n\r\nabc")
    assert_equal 200, whole.status
    assert_equal "3", whole.headers["content-length"]
    assert_equal "bytes", whole.headers["accept-ranges"]
    assert_equal "abc", whole.body

    partial = RangeClient.parse(
      "HTTP/1.1 206 Partial Content\r\ncontent-range: bytes 1-2/4\r\ncontent-length: 2\r\n\r\nbc"
    )
    assert_equal 206, partial.status
    assert_equal "bytes 1-2/4", partial.headers["content-range"]
    assert_equal "bc", partial.body
  end

  def test_parses_unsatisfiable_and_head_responses
    unsatisfiable = RangeClient.parse("HTTP/1.1 416 Range Not Satisfiable\r\ncontent-range: bytes */4\r\n\r\n")
    assert_equal 416, unsatisfiable.status
    assert_equal "bytes */4", unsatisfiable.headers["content-range"]
    assert_equal "", unsatisfiable.body

    head = RangeClient.parse("HTTP/1.1 200 OK\r\ncontent-length: 4\r\n\r\n")
    assert_equal 200, head.status
    assert_equal "4", head.headers["content-length"]
    assert_equal "", head.body
  end
end
