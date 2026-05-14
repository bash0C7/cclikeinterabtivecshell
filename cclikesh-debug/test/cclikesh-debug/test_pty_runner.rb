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
end
