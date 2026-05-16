require "test/unit"
require "tmpdir"
require "baslash/debug/spec_dsl"

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
    result = Baslash::Debug::SpecDSL.evaluate(src, db_path: @db_path, spec_path: "<inline>")
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
    result = Baslash::Debug::SpecDSL.evaluate(src, db_path: @db_path, spec_path: "<inline>")
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
    result = Baslash::Debug::SpecDSL.evaluate(src, db_path: @db_path, spec_path: "<inline>")
    assert_nil result.exit_status, "spawn that exceeds timeout must report nil exit_status"
  end

  def test_two_session_calls_raise
    src = <<~RUBY
      session("a") { spawn argv: ["/bin/echo"], cols: 1, rows: 1, env: {} }
      session("b") { spawn argv: ["/bin/echo"], cols: 1, rows: 1, env: {} }
    RUBY
    assert_raise(Baslash::Debug::SpecDSL::DslError) do
      Baslash::Debug::SpecDSL.evaluate(src, db_path: @db_path, spec_path: "<inline>")
    end
  end

  def test_missing_spawn_raises
    src = <<~RUBY
      session("noop") { wait 0.01 }
    RUBY
    assert_raise(Baslash::Debug::SpecDSL::DslError) do
      Baslash::Debug::SpecDSL.evaluate(src, db_path: @db_path, spec_path: "<inline>")
    end
  end

  def test_expect_blocks_run_after_session_and_aggregate_pass_fail
    src = <<~RUBY
      session "with expects" do
        spawn argv: ["/bin/echo", "OK-MARK"], cols: 40, rows: 10, env: {}
      end
      expect("output contains OK-MARK") { |c| c.contains?("OK-MARK") }
      expect("intentional failure")     { |_c| false }
    RUBY
    result = Baslash::Debug::SpecDSL.evaluate(src, db_path: @db_path, spec_path: "<inline>")
    outcomes = Baslash::Debug::SpecDSL.dispatch_expects(result)
    assert_equal "output contains OK-MARK", outcomes[0][:label]
    assert_equal true,  outcomes[0][:pass]
    assert_equal "intentional failure", outcomes[1][:label]
    assert_equal false, outcomes[1][:pass]
  end

  def test_expect_block_raising_counts_as_fail
    src = <<~RUBY
      session "boom" do
        spawn argv: ["/bin/echo", "x"], cols: 1, rows: 1, env: {}
      end
      expect("raises an error") { |_c| raise "kaboom" }
    RUBY
    result = Baslash::Debug::SpecDSL.evaluate(src, db_path: @db_path, spec_path: "<inline>")
    outcomes = Baslash::Debug::SpecDSL.dispatch_expects(result)
    assert_equal false, outcomes.first[:pass]
    assert_match(/kaboom/, outcomes.first[:error].to_s)
  end

  def test_clear_size_env_resize_and_diag_entries_round_trip
    require "tmpdir"
    src = <<~SPEC
      session "diag round trip" do
        timeout 5
        spawn argv: ["ruby", "-r", "io/console", "-e",
                     "STDOUT.sync=true; trap('WINCH'){p IO.console.winsize; exit 0}; sleep 2"],
              cols: 80,
              rows: 24,
              clear_size_env: true
        wait 0.3
        resize 120, 30
        wait 0.5
      end

      expect "post-resize size visible in output" do |c|
        c.contains?("[30, 120]")
      end
    SPEC

    db_path = File.join(Dir.tmpdir, "spec-dsl-diag-#{Process.pid}-#{rand(1<<32).to_s(16)}.sqlite")
    result = Baslash::Debug::SpecDSL.evaluate(src, db_path: db_path, spec_path: "(test)")
    assert_equal 0, result.exit_status
    outcomes = Baslash::Debug::SpecDSL.dispatch_expects(result)
    assert outcomes.first[:pass], "expect should pass; got #{outcomes.inspect}"
    # diag_entries: the spawned ruby process never required baslash, so
    # diag log will be empty — but it must still be an Array (not nil).
    assert_kind_of Array, result.captured.diag_entries
  ensure
    File.unlink(db_path) if db_path && File.exist?(db_path)
  end
end
