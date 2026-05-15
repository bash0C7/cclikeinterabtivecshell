require_relative "test_helper"
require "tmpdir"
require "curses"
require "cclikesh/style"
require "cclikesh/chrome"
require "cclikesh/display"

class TestDisplayLayoutDiag < Test::Unit::TestCase
  def setup
    @log_path = File.join(Dir.tmpdir, "display-diag-#{Process.pid}-#{rand(1<<32).to_s(16)}.log")
    @prev_env = ENV["CCLIKESH_LAYOUT_DIAG"]
    ENV["CCLIKESH_LAYOUT_DIAG"] = @log_path
    Curses.init_screen
    Curses.start_color
    Curses.use_default_colors
    Cclikesh::Style.init!
    Cclikesh::Chrome.init
    Cclikesh::Display.init
  end

  def teardown
    ENV["CCLIKESH_LAYOUT_DIAG"] = @prev_env
    Cclikesh::Display.close
    Cclikesh::Chrome.close
    Curses.close_screen
    File.unlink(@log_path) if File.exist?(@log_path)
  rescue
    nil
  end

  def test_refresh_emits_diag
    File.write(@log_path, "")
    Cclikesh::Display.refresh
    body = File.read(@log_path)
    assert_match(/Display\.refresh/, body)
  end
end
