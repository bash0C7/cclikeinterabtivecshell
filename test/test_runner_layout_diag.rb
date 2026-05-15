require_relative "test_helper"
require "tmpdir"
require "curses"
require "cclikesh/runner"

class TestRunnerLayoutDiag < Test::Unit::TestCase
  def setup
    @log_path = File.join(Dir.tmpdir, "runner-diag-#{Process.pid}-#{rand(1<<32).to_s(16)}.log")
    @prev_env = ENV["CCLIKESH_LAYOUT_DIAG"]
    ENV["CCLIKESH_LAYOUT_DIAG"] = @log_path
  end

  def teardown
    ENV["CCLIKESH_LAYOUT_DIAG"] = @prev_env
    File.unlink(@log_path) if File.exist?(@log_path)
    Curses.close_screen rescue nil
  end

  def test_init_curses_emits_diag_after_init_screen
    Cclikesh::Runner.init_curses
    assert File.exist?(@log_path), "diag log must exist after init_curses"
    body = File.read(@log_path)
    assert_match(/Runner\.init_curses\.after_init_screen/, body)
  end

  def test_sync_curses_to_terminal_size_emits_diag
    Curses.init_screen
    File.write(@log_path, "")  # truncate after init_screen so test only sees this call
    # Mock IO.console to return a valid winsize so the log call is reached
    mock_console = Object.new
    def mock_console.winsize
      [24, 80]
    end
    # Patch IO.console temporarily
    original_console = IO.method(:console)
    IO.define_singleton_method(:console) { mock_console }
    begin
      Cclikesh::Runner.sync_curses_to_terminal_size
      body = File.read(@log_path)
      assert_match(/Runner\.sync_curses_to_terminal_size/, body)
    ensure
      IO.define_singleton_method(:console, original_console)
    end
  end
end
