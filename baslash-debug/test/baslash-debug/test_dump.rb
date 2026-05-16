require "test/unit"
require "tmpdir"
require "stringio"
require "baslash/debug/pty_storage"
require "baslash/debug/dump"

class TestDump < Test::Unit::TestCase
  def setup
    @db = File.join(Dir.tmpdir, "test-dump-#{Process.pid}-#{rand(10000)}.sqlite")
    @storage = Baslash::Debug::PtyStorage.open(@db)
    @uuid = "dump-#{rand(1<<32).to_s(16)}"
    @storage.insert_session(uuid: @uuid, argv: ["echo"], cols: 1, rows: 1,
                            env: {}, spec_path: nil, timeout_sec: 1.0)
    @storage.insert_event(session_uuid: @uuid, ts: 0.10, dir: "i", bytes: "AB")
    @storage.insert_event(session_uuid: @uuid, ts: 0.20, dir: "o", bytes: "\x1b[31mX")
  end

  def teardown
    @storage.close
    [@db, "#{@db}-wal", "#{@db}-shm"].each { |f| File.unlink(f) if File.exist?(f) }
  end

  def test_dump_includes_ts_dir_hex_and_printable_ascii
    io = StringIO.new
    Baslash::Debug::Dump.to_io(db_path: @db, session_uuid: @uuid, io: io, io_filter: "both")
    lines = io.string.lines.map(&:chomp)
    assert lines.any? { |l| l.match?(/^0\.100\s+i\s+41 42\s+\|AB\|$/) }, lines.inspect
    assert lines.any? { |l| l.match?(/^0\.200\s+o\s+1b 5b 33 31 6d 58\s+\|\.\[31mX\|$/) }, lines.inspect
  end

  def test_dump_io_filter_input_only
    io = StringIO.new
    Baslash::Debug::Dump.to_io(db_path: @db, session_uuid: @uuid, io: io, io_filter: "i")
    refute_match(/^0\.200/, io.string)
    assert_match(/^0\.100/, io.string)
  end

  def test_dump_io_filter_output_only
    io = StringIO.new
    Baslash::Debug::Dump.to_io(db_path: @db, session_uuid: @uuid, io: io, io_filter: "o")
    refute_match(/^0\.100/, io.string)
    assert_match(/^0\.200/, io.string)
  end
end
