require "test/unit"
require "stringio"
require "baslash/title_bar"

class TestTitleBar < Test::Unit::TestCase
  def setup
    @orig_stdout = $stdout
    $stdout = StringIO.new
    Baslash::TitleBar.reset_for_test
  end

  def teardown
    $stdout = @orig_stdout
  end

  def test_set_emits_osc0_sequence
    Baslash::TitleBar.set("hello")
    assert_equal "\e]0;hello\a", $stdout.string
  end

  def test_set_strips_unsafe_bytes
    Baslash::TitleBar.set("a\ab\ec")
    assert_equal "\e]0;abc\a", $stdout.string
  end

  def test_restore_emits_empty_title
    Baslash::TitleBar.restore
    assert_equal "\e]0;\a", $stdout.string
  end

  def test_tick_ready_uses_static_glyph
    Baslash::TitleBar.tick(phase: :ready, ctx_text: "ready text")
    assert_match(/\A\e\]0;✻ ready text\a\z/, $stdout.string)
  end

  def test_tick_working_advances_spinner
    Baslash::TitleBar.tick(phase: :working, ctx_text: "x")
    first = $stdout.string.dup
    $stdout.truncate(0); $stdout.rewind
    Baslash::TitleBar.tick(phase: :working, ctx_text: "x")
    second = $stdout.string
    refute_equal first, second, "spinner glyph should advance between ticks while working"
  end

  def test_tick_count_increments
    initial = Baslash::TitleBar.tick_count
    Baslash::TitleBar.tick(phase: :ready, ctx_text: "a")
    assert_equal initial + 1, Baslash::TitleBar.tick_count
  end
end
