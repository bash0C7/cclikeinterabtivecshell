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

  def test_apply_named_color_via_apply
    assert_equal "\e[31mhi\e[0m", Baslash::Style.apply(:red, "hi")
    assert_equal "\e[36mhi\e[0m", Baslash::Style.apply(:cyan, "hi")
  end

  # --- Semantic styles (framework-emitted content) ---

  def test_apply_semantic_ok_is_green
    assert_equal "\e[32mexit 0\e[0m", Baslash::Style.apply(:ok, "exit 0")
  end

  def test_apply_semantic_ng_is_red
    assert_equal "\e[31mexit 1\e[0m", Baslash::Style.apply(:ng, "exit 1")
  end

  def test_apply_semantic_error_is_red
    assert_equal "\e[31mfailed\e[0m", Baslash::Style.apply(:error, "failed")
  end

  def test_apply_semantic_warn_is_yellow
    assert_equal "\e[33mcareful\e[0m", Baslash::Style.apply(:warn, "careful")
  end

  def test_apply_semantic_thinking_is_dim_cyan
    assert_equal "\e[2;36mrunning...\e[0m", Baslash::Style.apply(:thinking, "running...")
  end

  def test_apply_semantic_meta_is_dim_cyan
    assert_equal "\e[2;36m(detail)\e[0m", Baslash::Style.apply(:meta, "(detail)")
  end

  def test_apply_result_is_passthrough_for_impl_output
    # :result is impl execution output — framework does not color it so the
    # user's default terminal color shines through.
    assert_equal "stdout line", Baslash::Style.apply(:result, "stdout line")
  end

  def test_apply_unknown_is_passthrough
    assert_equal "hi", Baslash::Style.apply(:never_heard_of_it, "hi")
  end

  def test_strip_removes_sgr_escapes
    assert_equal "hi", Baslash::Style.strip("\e[1mhi\e[0m")
    assert_equal "ab", Baslash::Style.strip("\e[31ma\e[0m\e[32mb\e[0m")
  end
end
