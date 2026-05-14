require "test/unit"
require "tmpdir"
require "cclikesh/debug/spec_dsl"

class TestSpecDsl < Test::Unit::TestCase
  def setup
    @db_path = File.join(Dir.tmpdir, "test-dsl-#{Process.pid}-#{rand(10000)}.sqlite")
  end

  def teardown
    [@db_path, "#{@db_path}-wal", "#{@db_path}-shm"].each { |f| File.unlink(f) if File.exist?(f) }
  end

  def test_session_block_runs_spawn_and_records_output
    src = <<~RUBY
      session "echo session" do
        spawn argv: ["/bin/echo", "from-dsl"], cols: 40, rows: 10, env: {}
      end
    RUBY
    result = Cclikesh::Debug::SpecDSL.evaluate(src, db_path: @db_path, spec_path: "<inline>")
    assert_not_nil result.session_uuid
    assert_equal 0, result.exit_status
    assert_match(/from-dsl/, result.captured.output_text)
  end

  def test_send_writes_input_events
    src = <<~RUBY
      session "cat session" do
        spawn argv: ["/bin/cat"], cols: 40, rows: 10, env: {}
        send "hello\\n"
        wait 0.2
        send "\\x04"
      end
    RUBY
    result = Cclikesh::Debug::SpecDSL.evaluate(src, db_path: @db_path, spec_path: "<inline>")
    assert_match(/hello/, result.captured.output_text)
    assert_includes result.captured.input_log, "hello\n"
  end

  def test_timeout_override_in_session_body
    src = <<~RUBY
      session "slow" do
        timeout 0.3
        spawn argv: ["/bin/sh", "-c", "sleep 30"], cols: 1, rows: 1, env: {}
      end
    RUBY
    result = Cclikesh::Debug::SpecDSL.evaluate(src, db_path: @db_path, spec_path: "<inline>")
    assert_nil result.exit_status, "spawn that exceeds timeout must report nil exit_status"
  end

  def test_two_session_calls_raise
    src = <<~RUBY
      session("a") { spawn argv: ["/bin/echo"], cols: 1, rows: 1, env: {} }
      session("b") { spawn argv: ["/bin/echo"], cols: 1, rows: 1, env: {} }
    RUBY
    assert_raise(Cclikesh::Debug::SpecDSL::DslError) do
      Cclikesh::Debug::SpecDSL.evaluate(src, db_path: @db_path, spec_path: "<inline>")
    end
  end

  def test_missing_spawn_raises
    src = <<~RUBY
      session("noop") { wait 0.01 }
    RUBY
    assert_raise(Cclikesh::Debug::SpecDSL::DslError) do
      Cclikesh::Debug::SpecDSL.evaluate(src, db_path: @db_path, spec_path: "<inline>")
    end
  end
end
