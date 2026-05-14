require "test/unit"
require "tmpdir"
require "extralite"
require "cclikesh/debug/pty_storage"

class TestPtyStorage < Test::Unit::TestCase
  def setup
    @path = File.join(Dir.tmpdir, "test-pty-#{Process.pid}-#{rand(10000)}.sqlite")
    @s = Cclikesh::Debug::PtyStorage.open(@path)
  end

  def teardown
    @s.close
    [@path, "#{@path}-wal", "#{@path}-shm"].each { |f| File.unlink(f) if File.exist?(f) }
  end

  def test_schema_is_created_lazily_on_open
    rows = @s.db.query("SELECT name FROM sqlite_master WHERE type='table' ORDER BY name").map { |r| r[:name] }
    assert_includes rows, "pty_sessions"
    assert_includes rows, "pty_events"
  end

  def test_insert_session_round_trip
    @s.insert_session(
      uuid: "u1", argv: ["echo", "hi"], cols: 80, rows: 24,
      env: { "TERM" => "xterm-256color" }, spec_path: "/tmp/spec.rb",
      timeout_sec: 30.0
    )
    info = @s.fetch_session("u1")
    assert_equal "u1", info[:uuid]
    assert_equal ["echo", "hi"], info[:argv]
    assert_equal 80, info[:cols]
    assert_equal "xterm-256color", info[:env]["TERM"]
    assert_equal 30.0, info[:timeout_sec]
    assert_nil info[:ended_at]
    assert_nil info[:exit_status]
  end

  def test_insert_event_and_iterate_in_ts_order
    @s.insert_session(uuid: "u2", argv: ["cat"], cols: 80, rows: 24,
                      env: {}, spec_path: nil, timeout_sec: 30.0)
    @s.insert_event(session_uuid: "u2", ts: 0.20, dir: "o", bytes: "world")
    @s.insert_event(session_uuid: "u2", ts: 0.10, dir: "i", bytes: "hi\n")
    events = @s.each_event("u2").to_a
    assert_equal 2, events.size
    assert_equal "i",   events[0][:dir]
    assert_equal "hi\n", events[0][:bytes]
    assert_equal "o",   events[1][:dir]
    assert_equal "world", events[1][:bytes]
  end

  def test_mark_ended_sets_exit_status
    @s.insert_session(uuid: "u3", argv: ["echo"], cols: 1, rows: 1,
                      env: {}, spec_path: nil, timeout_sec: 30.0)
    @s.mark_ended(uuid: "u3", exit_status: 0)
    info = @s.fetch_session("u3")
    refute_nil info[:ended_at]
    assert_equal 0, info[:exit_status]
  end

  def test_list_sessions_returns_metadata_summary
    @s.insert_session(uuid: "u4", argv: ["echo", "a"], cols: 1, rows: 1,
                      env: {}, spec_path: nil, timeout_sec: 30.0)
    @s.insert_session(uuid: "u5", argv: ["echo", "b"], cols: 1, rows: 1,
                      env: {}, spec_path: nil, timeout_sec: 30.0)
    rows = @s.list_sessions
    uuids = rows.map { |r| r[:uuid] }
    assert_includes uuids, "u4"
    assert_includes uuids, "u5"
  end

  def test_open_twice_does_not_duplicate_schema
    @s.close
    @s = Cclikesh::Debug::PtyStorage.open(@path)
    @s.insert_session(uuid: "u6", argv: ["echo"], cols: 1, rows: 1,
                      env: {}, spec_path: nil, timeout_sec: 30.0)
    assert_equal "u6", @s.fetch_session("u6")[:uuid]
  end

  def test_fk_rejects_event_with_dangling_session_uuid
    assert_raise(Extralite::Error) do
      @s.insert_event(session_uuid: "nonexistent", ts: 0.0, dir: "o", bytes: "x")
    end
  end
end
