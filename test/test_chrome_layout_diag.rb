require_relative "test_helper"
require "tmpdir"
require "curses"
require "cclikesh/style"
require "cclikesh/chrome"

class TestChromeLayoutDiag < Test::Unit::TestCase
  def setup
    @log_path = File.join(Dir.tmpdir, "chrome-diag-#{Process.pid}-#{rand(1<<32).to_s(16)}.log")
    @prev_env = ENV["CCLIKESH_LAYOUT_DIAG"]
    ENV["CCLIKESH_LAYOUT_DIAG"] = @log_path
    Curses.init_screen
    Curses.start_color
    Curses.use_default_colors
    Cclikesh::Style.init!
  end

  def teardown
    ENV["CCLIKESH_LAYOUT_DIAG"] = @prev_env
    Cclikesh::Chrome.close
    Curses.close_screen
    File.unlink(@log_path) if File.exist?(@log_path)
  rescue
    nil
  end

  def test_chrome_init_emits_tag
    File.write(@log_path, "")
    Cclikesh::Chrome.init
    body = File.read(@log_path)
    assert_match(/Chrome\.init/, body)
    assert_match(/Chrome\.draw_dividers/, body)  # init calls draw_dividers internally
  end

  def test_handle_resize_emits_before_and_after_tags
    Cclikesh::Chrome.init
    File.write(@log_path, "")
    Cclikesh::Chrome.handle_resize
    body = File.read(@log_path)
    assert_match(/Chrome\.handle_resize\.before/, body)
    assert_match(/Chrome\.handle_resize\.after_resizeterm/, body)
  end
end
