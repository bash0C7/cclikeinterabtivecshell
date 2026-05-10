require "test/unit"
require "json"
require "stringio"
require "cclikesh/debug/cast_writer"

class TestCastWriter < Test::Unit::TestCase
  def test_writes_v2_header_first_line
    io = StringIO.new
    Cclikesh::Debug::CastWriter.write(io, frames: [], rows: 24, cols: 80, started_at: 1234567890)
    first = io.string.lines.first
    header = JSON.parse(first)
    assert_equal 2, header["version"]
    assert_equal 80, header["width"]
    assert_equal 24, header["height"]
    assert_equal 1234567890, header["timestamp"]
  end

  def test_each_frame_is_o_event_line
    frames = [
      { ts: 0.10, raw_bytes: "hello" },
      { ts: 0.50, raw_bytes: "world" }
    ]
    io = StringIO.new
    Cclikesh::Debug::CastWriter.write(io, frames: frames, rows: 24, cols: 80, started_at: 0)
    lines = io.string.lines.drop(1)
    assert_equal 2, lines.size
    e0 = JSON.parse(lines[0])
    assert_equal 0.10, e0[0]
    assert_equal "o",  e0[1]
    assert_equal "hello", e0[2]
  end

  def test_skips_empty_raw_bytes_frames
    frames = [
      { ts: 0.10, raw_bytes: "hello" },
      { ts: 0.20, raw_bytes: "" },        # skip
      { ts: 0.30, raw_bytes: "world" }
    ]
    io = StringIO.new
    Cclikesh::Debug::CastWriter.write(io, frames: frames, rows: 24, cols: 80, started_at: 0)
    lines = io.string.lines.drop(1)
    assert_equal 2, lines.size
  end
end
