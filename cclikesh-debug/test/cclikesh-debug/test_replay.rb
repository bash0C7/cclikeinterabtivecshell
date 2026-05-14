require "test/unit"
require "tmpdir"
require "stringio"
require "cclikesh/debug/spec_dsl"
require "cclikesh/debug/replay"

class TestReplay < Test::Unit::TestCase
  def setup
    @db = File.join(Dir.tmpdir, "test-replay-#{Process.pid}-#{rand(10000)}.sqlite")
    src = <<~RUBY
      session "replay seed" do
        spawn argv: ["/bin/echo", "ABCDEF"], cols: 40, rows: 10, env: {}
      end
    RUBY
    result = Cclikesh::Debug::SpecDSL.evaluate(src, db_path: @db, spec_path: "<inline>")
    @uuid = result.session_uuid
  end

  def teardown
    [@db, "#{@db}-wal", "#{@db}-shm"].each { |f| File.unlink(f) if File.exist?(f) }
  end

  def test_speed_zero_emits_full_output_in_under_100ms
    io = StringIO.new
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    Cclikesh::Debug::Replay.to_io(db_path: @db, session_uuid: @uuid, io: io, speed: 0)
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
    assert elapsed < 0.1, "speed:0 replay must finish < 100ms, got #{elapsed.round(3)}"
    assert_match(/ABCDEF/, io.string)
  end

  def test_replay_only_emits_output_events_not_input_or_exit
    require "cclikesh/debug/pty_storage"
    storage = Cclikesh::Debug::PtyStorage.open(@db)
    uuid2 = "mixed-#{rand(1<<32).to_s(16)}"
    begin
      storage.insert_session(uuid: uuid2, argv: ["x"], cols: 1, rows: 1,
                              env: {}, spec_path: nil, timeout_sec: 1.0)
      storage.insert_event(session_uuid: uuid2, ts: 0.0, dir: "i", bytes: "INPUT-ONLY")
      storage.insert_event(session_uuid: uuid2, ts: 0.1, dir: "o", bytes: "OUTPUT-ONLY")
      storage.insert_event(session_uuid: uuid2, ts: 0.2, dir: "x", bytes: "0")
    ensure
      storage.close
    end
    io = StringIO.new
    Cclikesh::Debug::Replay.to_io(db_path: @db, session_uuid: uuid2, io: io, speed: 0)
    refute_includes io.string, "INPUT-ONLY"
    refute_match(/\b0\b/, io.string.sub("OUTPUT-ONLY", ""))
    assert_match(/OUTPUT-ONLY/, io.string)
  end

  def test_replay_of_unknown_uuid_emits_nothing
    io = StringIO.new
    Cclikesh::Debug::Replay.to_io(db_path: @db, session_uuid: "no-such-uuid", io: io, speed: 0)
    assert_equal "", io.string
  end
end
