require "test/unit"
require "tmpdir"
require "stringio"
require "baslash/debug/pty_storage"
require "baslash/debug/pty_list"

class TestPtyList < Test::Unit::TestCase
  def setup
    @db = File.join(Dir.tmpdir, "test-list-#{Process.pid}-#{rand(10000)}.sqlite")
    @s  = Baslash::Debug::PtyStorage.open(@db)
    @s.insert_session(uuid: "older", argv: ["echo", "old"], cols: 1, rows: 1,
                      env: {}, spec_path: nil, timeout_sec: 1.0)
    @s.mark_ended(uuid: "older", exit_status: 0)
    sleep 0.01
    @s.insert_session(uuid: "newer", argv: ["echo", "new"], cols: 1, rows: 1,
                      env: {}, spec_path: "/tmp/x.rb", timeout_sec: 30.0)
  end

  def teardown
    @s.close
    [@db, "#{@db}-wal", "#{@db}-shm"].each { |f| File.unlink(f) if File.exist?(f) }
  end

  def test_list_emits_newest_first
    io = StringIO.new
    Baslash::Debug::PtyList.to_io(db_path: @db, io: io)
    lines = io.string.lines
    assert_operator lines.size, :>=, 3
    assert_match(/newer/, lines[1])
    assert_match(/older/, lines[2])
  end

  def test_list_includes_argv_and_status_columns
    io = StringIO.new
    Baslash::Debug::PtyList.to_io(db_path: @db, io: io)
    body = io.string
    assert_match(/uuid\s+started_at\s+exit\s+argv/i, body.lines.first)
    assert_match(/older.+0\s.+echo old/, body)
    assert_match(/newer.+-\s.+echo new/, body)
  end
end
