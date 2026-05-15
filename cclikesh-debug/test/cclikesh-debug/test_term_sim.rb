require "test/unit"
require "cclikesh/debug/term_sim"

class TestTermSim < Test::Unit::TestCase
  def setup
    @sim = Cclikesh::Debug::TermSim.new(10, 20)
  end

  def test_initial_state
    assert_equal 1, @sim.row
    assert_equal 1, @sim.col
    assert_equal 1, @sim.scroll_top
    assert_equal 10, @sim.scroll_bottom
    assert_equal 10, @sim.grid.size
    @sim.grid.each { |line| assert_equal " " * 20, line }
  end

  def test_printable_advances_cursor
    @sim.feed("hi")
    assert_equal "hi" + " " * 18, @sim.grid[0]
    assert_equal 1, @sim.row
    assert_equal 3, @sim.col
  end

  def test_crlf_moves_to_next_row_col1
    @sim.feed("ab\r\ncd")
    assert_equal "ab" + " " * 18, @sim.grid[0]
    assert_equal "cd" + " " * 18, @sim.grid[1]
    assert_equal 2, @sim.row
    assert_equal 3, @sim.col
  end

  def test_cup_moves_cursor
    @sim.feed("\e[5;3H")
    assert_equal 5, @sim.row
    assert_equal 3, @sim.col
    @sim.feed("X")
    assert_equal "  X" + " " * 17, @sim.grid[4]
  end

  def test_decsc_decrc_save_restore
    @sim.feed("\e[3;5HA\e7")  # cursor (3,5), write A (now col=6), save at (3,6)
    @sim.feed("\e[7;1HB")     # write B at (7,1)
    @sim.feed("\e8C")         # restore to (3,6), write C at (3,6)
    assert_equal "    AC" + " " * 14, @sim.grid[2]
    assert_equal "B" + " " * 19, @sim.grid[6]
  end

  def test_dec_graphics_q_renders_horizontal
    @sim.feed("\e(0qq\e(B")
    assert_equal "──" + " " * 18, @sim.grid[0]
  end

  def test_rep_repeats_preceding_char
    # \e[5b = repeat preceding char 5 times
    @sim.feed("\e(0q\e[5bq\e(B")  # 1 q + 5 reps + 1 q = 7 ─
    expected = "─" * 7 + " " * 13
    assert_equal expected, @sim.grid[0]
  end

  def test_decstbm_scroll_within_region
    sim = Cclikesh::Debug::TermSim.new(5, 10)
    sim.feed("\e[1;1HAA\r\n\e[2;1HBB\r\n\e[3;1HCC")
    # Now: row1=AA, row2=BB, row3=CC
    sim.feed("\e[1;3r")  # scroll region 1-3
    sim.feed("\e[3;1H\n")  # at row 3, LF -> scroll region 1-3 up; row1 dropped, row3 blank
    assert_equal "BB" + " " * 8, sim.grid[0]
    assert_equal "CC" + " " * 8, sim.grid[1]
    assert_equal " " * 10, sim.grid[2]
  end

  def test_lf_at_scroll_bottom_scrolls_not_below
    sim = Cclikesh::Debug::TermSim.new(3, 5)
    sim.feed("AA\r\nBB\r\nCC")
    sim.feed("\n")  # at row 3 col 3, LF -> scroll up; row 1 dropped, row 3 blank
    assert_equal "BB" + " " * 3, sim.grid[0]
    assert_equal "CC" + " " * 3, sim.grid[1]
    assert_equal " " * 5, sim.grid[2]
  end

  def test_el_erase_to_eol
    @sim.feed("HELLO")
    @sim.feed("\e[1;3H\e[K")  # cursor to (1,3), erase to EOL
    assert_equal "HE" + " " * 18, @sim.grid[0]
  end

  def test_find_row_substring
    @sim.feed("\e[3;5HHello\e[7;1HWorld")
    assert_equal 3, @sim.find_row("Hello")
    assert_equal 7, @sim.find_row("World")
    assert_nil   @sim.find_row("missing")
  end

  def test_find_row_regex
    @sim.feed("\e[5;1Hfoo123bar")
    assert_equal 5, @sim.find_row(/foo\d+bar/)
  end

  def test_decstbm_with_decsc_decrc_no_visible_motion
    # Reproduces the cclikesh /heko reply byte stream pattern: write at row N,
    # emit several LF that move cursor without scrolling, restore via DECRC.
    sim = Cclikesh::Debug::TermSim.new(40, 120)
    # Simulate cursor anchored at row 36 col 1 (prompt row).
    sim.feed("\e[36;1H\e7")  # save at (36,1)
    # Body update: temp scroll region 1-34, scroll within it, restore region.
    sim.feed("\e[1;34r\e[34;1H\n")  # scrolls rows 1-34 up by 1
    sim.feed("\e[1;40r\e[34;1H")    # restore region, cursor to (34,1)
    sim.feed("Unknown command: /heko")
    sim.feed("\r\n\n\n\n")           # 4 LF — none cause scroll (cursor 34->38, scroll bottom is 40)
    sim.feed("\e8")                  # restore cursor to (36,1)
    # The 4 LF moved cursor to row 38 but did not scroll anything (region is 1-40,
    # cursor never reached row 40). DECRC restored cursor to (36,1).
    assert_equal "Unknown command: /heko" + " " * (120 - 22), sim.grid[33]
    assert_equal " " * 120, sim.grid[34]
    assert_equal " " * 120, sim.grid[35]
    assert_equal 36, sim.row
    assert_equal 1, sim.col
  end
end
