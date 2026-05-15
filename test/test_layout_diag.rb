require_relative "test_helper"
require "tmpdir"
require "cclikesh/layout_diag"

class TestLayoutDiag < Test::Unit::TestCase
  def setup
    @log_path = File.join(Dir.tmpdir, "layout-diag-test-#{Process.pid}-#{rand(1<<32).to_s(16)}.log")
    @prev_env = ENV["CCLIKESH_LAYOUT_DIAG"]
  end

  def teardown
    ENV["CCLIKESH_LAYOUT_DIAG"] = @prev_env
    File.unlink(@log_path) if File.exist?(@log_path)
  end

  def test_no_op_when_env_unset
    ENV["CCLIKESH_LAYOUT_DIAG"] = nil
    Cclikesh::LayoutDiag.log("noop")
    refute File.exist?(@log_path), "no file should be created when env unset"
  end

  def test_no_op_when_env_blank
    ENV["CCLIKESH_LAYOUT_DIAG"] = ""
    Cclikesh::LayoutDiag.log("noop")
    refute File.exist?(@log_path), "no file when env blank"
  end

  def test_appends_one_line_per_call
    ENV["CCLIKESH_LAYOUT_DIAG"] = @log_path
    Cclikesh::LayoutDiag.log("first")
    Cclikesh::LayoutDiag.log("second")
    lines = File.readlines(@log_path)
    assert_equal 2, lines.size
    assert_match(/\bfirst\b/, lines[0])
    assert_match(/\bsecond\b/, lines[1])
  end

  def test_line_contains_expected_fields
    ENV["CCLIKESH_LAYOUT_DIAG"] = @log_path
    Cclikesh::LayoutDiag.log("Chrome.init")
    line = File.read(@log_path)
    assert_match(/^\[\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}/, line)  # iso8601(3)
    assert_match(/Chrome\.init/, line)
    assert_match(/curses\.lines=/, line)
    assert_match(/curses\.cols=/, line)
    assert_match(/maxyx=/, line)
    assert_match(/winsize=/, line)
    assert_match(/env_lines=/, line)
    assert_match(/env_cols=/, line)
  end

  def test_swallows_disk_failure
    ENV["CCLIKESH_LAYOUT_DIAG"] = "/nonexistent_dir_for_diag_test/diag.log"
    assert_nothing_raised do
      Cclikesh::LayoutDiag.log("disk-fail")
    end
  end
end
