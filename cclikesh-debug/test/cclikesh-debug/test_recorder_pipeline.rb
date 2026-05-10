require "test/unit"
require "tmpdir"
require "json"
require "cclikesh/debug/recorder"
require "cclikesh/debug/storage"

class TestRecorderPipeline < Test::Unit::TestCase
  class StubEmbedder
    def embed(_text); Array.new(768) { 0.001 }; end
  end

  def test_orchestrator_drains_one_frame_through_pipeline
    db_path = File.join(Dir.tmpdir, "test-pipeline-#{Process.pid}-#{rand(10000)}.sqlite")
    storage = Cclikesh::Debug::Storage.create(db_path,
      session_uuid: "test-uuid", shell_argv: [], cclikesh_ver: "0.2.0",
      rows: 24, cols: 80, embedder: "stub")

    rec = Cclikesh::Debug::Recorder.new(storage: storage,
                                         embedder_factory: -> { StubEmbedder.new },
                                         no_vector: false)
    rec.synthetic_frame!(ts: 0.1, content: "hello", framework_state: { phase: "idle" })
    rec.drain_one_cycle!

    rows = storage.db.execute("SELECT id, content FROM frames")
    assert_equal 1, rows.size
    assert_equal "hello", rows[0][1]

    vec_count = storage.db.execute("SELECT COUNT(*) FROM frame_vec").first[0]
    assert_equal 1, vec_count
  ensure
    rec&.stop!
    storage&.close
    [db_path, "#{db_path}-wal", "#{db_path}-shm"].each { |f| File.unlink(f) if f && File.exist?(f) }
  end

  def test_no_vector_skips_embedding
    db_path = File.join(Dir.tmpdir, "test-pipeline-novec-#{Process.pid}-#{rand(10000)}.sqlite")
    storage = Cclikesh::Debug::Storage.create(db_path,
      session_uuid: "test-uuid", shell_argv: [], cclikesh_ver: "0.2.0",
      rows: 24, cols: 80, embedder: "none")
    rec = Cclikesh::Debug::Recorder.new(storage: storage,
                                         embedder_factory: -> { StubEmbedder.new },
                                         no_vector: true)
    rec.synthetic_frame!(ts: 0.5, content: "x", framework_state: {})
    rec.drain_one_cycle!
    vec_count = storage.db.execute("SELECT COUNT(*) FROM frame_vec").first[0]
    assert_equal 0, vec_count
  ensure
    rec&.stop!
    storage&.close
    [db_path, "#{db_path}-wal", "#{db_path}-shm"].each { |f| File.unlink(f) if f && File.exist?(f) }
  end
end
