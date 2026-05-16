require "test/unit"
require "tmpdir"
require "json"
require "baslash/debug/recorder"
require "baslash/debug/storage"
require "baslash/debug/ractors/storage_writer"

class TestRecorderPipeline < Test::Unit::TestCase
  class StubEmbedder
    def embed(_text); Array.new(768) { 0.001 }; end
  end

  def test_storage_writer_ractor_writes_via_extralite
    db_path = File.join(Dir.tmpdir, "test-pipeline-#{Process.pid}-#{rand(10000)}.sqlite")
    storage = Baslash::Debug::Storage.create(db_path,
      session_uuid: "u", shell_argv: [], baslash_ver: "0.2.0",
      rows: 24, cols: 80, embedder: "stub")
    storage.close

    writer = Baslash::Debug::Ractors::StorageWriter.spawn(db_path: db_path)
    frame = {
      ts: 0.1, trigger: "on_demand", event_kind: nil,
      cursor_row: 0, cursor_col: 0,
      raw_bytes: "".b.freeze,
      framework_state_json: "{}", content: "hello"
    }.freeze
    writer.send([:frame, frame])
    writer.send([:stop])
    sleep 0.1

    ro = Baslash::Debug::Storage.open(db_path, readonly: true)
    rows = ro.db.query("SELECT id, content FROM frames")
    assert_equal 1, rows.size
    assert_equal "hello", rows[0][:content]
    ro.close
  ensure
    [db_path, "#{db_path}-wal", "#{db_path}-shm"].each { |f| File.unlink(f) if f && File.exist?(f) }
  end

  def test_no_vector_skips_embedding
    omit "rewritten in Case B (subprocess + DRb) flow, see Task 7"
  end

  def test_recorder_start_pipeline_writes_via_ractor
    db_path = File.join(Dir.tmpdir, "test-recorder-pipe-#{Process.pid}-#{rand(10000)}.sqlite")
    storage = Baslash::Debug::Storage.create(db_path,
      session_uuid: "u", shell_argv: [], baslash_ver: "0.2.0",
      rows: 24, cols: 80, embedder: "stub")

    read_io, write_io = IO.pipe

    rec = Baslash::Debug::Recorder.new(storage: storage,
                                         embedder_factory: -> { StubEmbedder.new },
                                         no_vector: true)
    rec.start_pipeline!(pty_master_fd: read_io.fileno)

    snap = { ts_shell: 0.5, cursor: [0, 0],
             framework_state: { phase: "idle", input: { buffer: "x" } } }
    rec.trigger_capture!(snapshot: snap, trigger: "on_demand", event_kind: nil)

    sleep 0.1  # let FrameBuilder process the snapshot before EOF cascade
    write_io.close  # triggers EOF in PtyReader → cascades :eof through pipeline
    rec.stop!
    storage.close

    ro = Baslash::Debug::Storage.open(db_path, readonly: true)
    rows = ro.db.query("SELECT id, content FROM frames")
    assert_equal 1, rows.size, "expected 1 frame written via Ractor pipeline"
    ro.close
  ensure
    read_io&.close
    write_io&.close rescue nil
    [db_path, "#{db_path}-wal", "#{db_path}-shm"].each { |f| File.unlink(f) if f && File.exist?(f) }
  end
end
