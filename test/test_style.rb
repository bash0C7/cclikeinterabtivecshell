require "test/unit"
require "stringio"
require "cclikesh/style"

class TestStyle < Test::Unit::TestCase
  def setup
    Cclikesh::Style.init!
  end

  def test_builtin_styles_emit_sgr_pairs
    on, off = Cclikesh::Style.lookup(:error)
    assert_equal "\e[31m", on
    assert_equal "\e[0m",  off
  end

  def test_dim_attr_only
    on, off = Cclikesh::Style.lookup(:dim)
    assert_equal "\e[2m", on
    assert_equal "\e[0m", off
  end

  def test_define_custom_with_fg
    Cclikesh::Style.define(:warn, fg: 214)
    on, off = Cclikesh::Style.lookup(:warn)
    assert_equal "\e[38;5;214m", on
    assert_equal "\e[0m",        off
  end

  def test_with_wraps_writes_in_sgr
    io = StringIO.new
    Cclikesh::Style.with(io, :error) { io.write("oops") }
    assert_equal "\e[31moops\e[0m", io.string
  end

  def test_lookup_unknown_returns_nil_pair
    on, off = Cclikesh::Style.lookup(:does_not_exist)
    assert_nil on
    assert_nil off
  end

  def test_with_unknown_style_passes_through
    io = StringIO.new
    Cclikesh::Style.with(io, :nope) { io.write("plain") }
    assert_equal "plain", io.string
  end
end
