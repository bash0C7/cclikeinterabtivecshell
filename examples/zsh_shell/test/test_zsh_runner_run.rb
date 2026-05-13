# frozen_string_literal: true

require "test/unit"
require "tmpdir"
require_relative "../zsh_runner"

class TestZshRunnerRun < Test::Unit::TestCase
  def setup
    @stdout = []
    @stderr = []
    @ticks = []
    @on_stdout = ->(l) { @stdout << l }
    @on_stderr = ->(l) { @stderr << l }
    @on_tick   = ->(s) { @ticks << s }
  end

  def run_line(line, cwd: Dir.pwd, env: ENV.to_h)
    ZshRunner.run(
      line,
      cwd: cwd,
      env: env,
      on_stdout: @on_stdout,
      on_stderr: @on_stderr,
      on_tick:   @on_tick
    )
  end

  def test_echo_to_stdout
    status, elapsed = run_line("echo hello")
    assert_equal "hello\n", @stdout.join
    assert_predicate status, :success?
    assert elapsed >= 0
  end

  def test_echo_to_stderr
    run_line("echo err 1>&2")
    assert_equal "err\n", @stderr.join
  end

  def test_nonzero_exit
    status, _ = run_line("exit 7")
    refute_predicate status, :success?
    assert_equal 7, status.exitstatus
  end

  def test_cwd_is_applied
    Dir.mktmpdir do |tmp|
      run_line("pwd", cwd: tmp)
      assert_equal File.realpath(tmp), File.realpath(@stdout.join.chomp)
    end
  end

  def test_env_is_applied
    run_line("echo $CCLIKESH_TEST_VAR", env: {"CCLIKESH_TEST_VAR" => "secret"})
    assert_equal "secret\n", @stdout.join
  end

  def test_tick_called_for_slow_command
    run_line("sleep 0.5")
    assert @ticks.length >= 1, "expected at least one tick, got #{@ticks.length}"
  end

  def test_multiple_stdout_lines
    run_line("printf 'a\\nb\\nc\\n'")
    assert_equal %W[a\n b\n c\n], @stdout
  end

  def test_invalid_utf8_bytes_do_not_crash
    status, _ = run_line("printf '\\xff\\xfe\\n'")
    assert_predicate status, :success?
    # The invalid bytes get replaced with "?" by set_encoding(invalid: :replace),
    # so we just verify we got a line and didn't raise.
    assert_equal 1, @stdout.length
  end
end
