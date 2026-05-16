require "test/unit"
require "baslash/style"

class TestStyle < Test::Unit::TestCase
  def test_bold_wraps_with_sgr
    assert_equal "\e[1mhi\e[0m", Baslash::Style.bold("hi")
  end

  def test_dim_wraps_with_sgr
    assert_equal "\e[2mhi\e[0m", Baslash::Style.dim("hi")
  end

  def test_color_wraps_with_named_color
    assert_equal "\e[31mhi\e[0m", Baslash::Style.color(:red, "hi")
    assert_equal "\e[32mhi\e[0m", Baslash::Style.color(:green, "hi")
  end

  def test_apply_named_style
    assert_equal "\e[1mhi\e[0m", Baslash::Style.apply(:bold, "hi")
    assert_equal "hi", Baslash::Style.apply(nil, "hi")
    assert_equal "hi", Baslash::Style.apply(:unknown, "hi")
  end

  def test_strip_removes_sgr_escapes
    assert_equal "hi", Baslash::Style.strip("\e[1mhi\e[0m")
    assert_equal "ab", Baslash::Style.strip("\e[31ma\e[0m\e[32mb\e[0m")
  end
end
