require "test/unit"
require "tmpdir"
require "cclikesh/debug/storage"

class TestDebugStorage < Test::Unit::TestCase
  def setup
    @path = File.join(Dir.tmpdir, "test-debug-#{Process.pid}-#{rand(10000)}.sqlite")
    @s = Cclikesh::Debug::Storage.create(@path,
      session_uuid: "abc-123",
      shell_argv:   ["ruby", "examples/echo_shell.rb"],
      cclikesh_ver: "0.2.0",
      rows: 24, cols: 80,
      embedder: "ruri-v3-310m-onnx", notes: "test session")
  end

  def teardown
    @s.close
    [@path, "#{@path}-wal", "#{@path}-shm"].each { |f| File.unlink(f) if File.exist?(f) }
  end

  def test_session_info_persists
    info = @s.session_info
    assert_equal "abc-123", info[:uuid]
    assert_equal 24, info[:rows]
    assert_equal "ruri-v3-310m-onnx", info[:embedder]
  end

  def test_insert_frame_returns_id
    fid = @s.insert_frame(
      ts: 0.5, trigger: "periodic", event_kind: nil,
      cursor_row: 10, cursor_col: 5,
      raw_bytes_zlib: nil,
      framework_state_json: '{"phase":"idle"}',
      content: "hello",
      source: "framework_state"
    )
    assert fid > 0
  end

  def test_select_frames_in_order
    @s.insert_frame(ts: 0.1, trigger: "periodic", event_kind: nil,
                    cursor_row: 0, cursor_col: 0, raw_bytes_zlib: nil,
                    framework_state_json: "{}", content: "a", source: "framework_state")
    @s.insert_frame(ts: 0.2, trigger: "periodic", event_kind: nil,
                    cursor_row: 0, cursor_col: 0, raw_bytes_zlib: nil,
                    framework_state_json: "{}", content: "b", source: "framework_state")
    rows = @s.select_frames(limit: 10)
    assert_equal 2, rows.size
    assert_equal "a", rows[0][:content]
  end

  def test_meta_seeds_inserted
    rows = @s.db.execute("SELECT object_type, object_name FROM _sqlite_mcp_meta")
    types = rows.map { |r| r[0] }
    assert_includes types, "db"
    assert_includes types, "table"
    assert_includes types, "recipe"
  end

  def test_upsert_frame_vec_inserts_blob
    fid = @s.insert_frame(ts: 0.5, trigger: "periodic", event_kind: nil,
                           cursor_row: 0, cursor_col: 0, raw_bytes_zlib: nil,
                           framework_state_json: "{}", content: "x", source: "framework_state")
    vec = Array.new(768) { 0.001 }
    @s.upsert_frame_vec(fid, vec)
    count = @s.db.execute("SELECT COUNT(*) FROM frame_vec").first[0]
    assert_equal 1, count
  end
end
