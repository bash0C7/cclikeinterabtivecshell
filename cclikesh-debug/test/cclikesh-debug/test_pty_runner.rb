require "test/unit"
require "cclikesh/debug/pty_runner"

class TestPtyRunner < Test::Unit::TestCase
  def collect(argv:, cols: 80, rows: 24, env: {}, timeout: 5.0, &script)
    events = []
    sink = ->(ts:, dir:, bytes:) { events << { ts: ts, dir: dir, bytes: bytes } }
    runner = Cclikesh::Debug::PtyRunner.new(
      argv: argv, cols: cols, rows: rows, env: env,
      timeout_sec: timeout, event_sink: sink
    )
    exit_status = runner.run(&script)
    [exit_status, events]
  end

  def test_echo_one_word
    status, events = collect(argv: ["/bin/echo", "hello"])
    assert_equal 0, status
    output = events.select { |e| e[:dir] == "o" }.map { |e| e[:bytes] }.join.b
    assert_match(/hello/, output)
  end

  def test_send_then_eof_drives_cat
    status, events = collect(argv: ["/bin/cat"], timeout: 3.0) do |sess|
      sess.send "hi\n"
      sess.wait 0.2
      sess.send "\x04"
    end
    assert_equal 0, status
    output = events.select { |e| e[:dir] == "o" }.map { |e| e[:bytes] }.join.b
    assert_match(/hi/, output)
    input = events.select { |e| e[:dir] == "i" }.map { |e| e[:bytes] }.join.b
    assert_includes input, "hi\n"
  end

  def test_records_nonzero_exit_status
    status, events = collect(argv: ["/bin/sh", "-c", "printf hi >&2; exit 7"])
    assert_equal 7, status
    last_x = events.reverse.find { |e| e[:dir] == "x" }
    assert_not_nil last_x
    assert_equal "7".b, last_x[:bytes]
  end

  def test_timeout_kills_child_and_marks_status_nil
    status, _events = collect(argv: ["/bin/sh", "-c", "sleep 30"], timeout: 0.5)
    assert_nil status
  end

  def test_events_are_monotonic_in_ts
    _status, events = collect(argv: ["/bin/echo", "ok"])
    tss = events.map { |e| e[:ts] }
    assert_equal tss, tss.sort, "events must be timestamp-sorted"
    assert tss.first >= 0.0
  end

  def test_runs_with_pty_storage_sink_and_persists_events
    require "tmpdir"
    require "cclikesh/debug/pty_storage"
    db_path = File.join(Dir.tmpdir, "test-runner-store-#{Process.pid}-#{rand(10000)}.sqlite")
    storage = Cclikesh::Debug::PtyStorage.open(db_path)
    begin
      uuid = "runner-#{rand(1<<32).to_s(16)}"
      storage.insert_session(uuid: uuid, argv: ["/bin/echo", "ok"],
                             cols: 80, rows: 24, env: {},
                             spec_path: nil, timeout_sec: 5.0)
      sink = ->(ts:, dir:, bytes:) {
        storage.insert_event(session_uuid: uuid, ts: ts, dir: dir, bytes: bytes)
      }
      runner = Cclikesh::Debug::PtyRunner.new(
        argv: ["/bin/echo", "ok"], cols: 80, rows: 24, env: {},
        timeout_sec: 5.0, event_sink: sink
      )
      status = runner.run
      storage.mark_ended(uuid: uuid, exit_status: status)
      events = storage.each_event(uuid).to_a
      output = events.select { |e| e[:dir] == "o" }.map { |e| e[:bytes] }.join.b
      assert_match(/ok/, output)
      assert_equal 0, storage.fetch_session(uuid)[:exit_status]
    ensure
      storage.close
      [db_path, "#{db_path}-wal", "#{db_path}-shm"].each { |f| File.unlink(f) if File.exist?(f) }
    end
  end

  def test_clear_size_env_strips_lines_and_columns
    @ev = []
    sink = ->(ts:, dir:, bytes:) { @ev << { ts: ts, dir: dir, bytes: bytes } }
    runner = Cclikesh::Debug::PtyRunner.new(
      argv:        ["/usr/bin/env"],
      cols:        120,
      rows:        40,
      env:         { "COLUMNS" => "999", "LINES" => "999" }, # deliberately bogus to prove they're cleared
      timeout_sec: 5.0,
      event_sink:  sink,
      clear_size_env: true,
    )
    status = runner.run
    output = @ev.select { |e| e[:dir] == "o" }.map { |e| e[:bytes] }.join.b
    assert_equal 0, status
    assert_no_match(/COLUMNS\s*=/, output, "COLUMNS must not appear in env output")
    assert_no_match(/LINES\s*=/,   output, "LINES must not appear in env output")
  end

  def test_clear_size_env_default_false_preserves_existing_behavior
    @ev = []
    sink = ->(ts:, dir:, bytes:) { @ev << { ts: ts, dir: dir, bytes: bytes } }
    runner = Cclikesh::Debug::PtyRunner.new(
      argv:        ["/usr/bin/env"],
      cols:        120,
      rows:        40,
      env:         {},
      timeout_sec: 5.0,
      event_sink:  sink,
    )
    status = runner.run
    output = @ev.select { |e| e[:dir] == "o" }.map { |e| e[:bytes] }.join.b
    assert_equal 0, status
    assert_match(/COLUMNS\s*=\s*120/, output)
    assert_match(/LINES\s*=\s*40/,    output)
  end
end
