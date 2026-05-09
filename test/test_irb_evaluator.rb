# frozen_string_literal: true

require_relative "test_helper"
require_relative "../examples/irb_shell/irb_evaluator"

class TestIrbEvaluator < Test::Unit::TestCase
  def test_evaluates_simple_expression
    evaluator = IrbEvaluator.new
    assert_equal 3, evaluator.evaluate("1 + 2")
  end

  def test_persists_local_variables_across_calls
    evaluator = IrbEvaluator.new
    evaluator.evaluate("x = 10")
    assert_equal 30, evaluator.evaluate("x * 3")
  end

  def test_persists_method_definitions
    evaluator = IrbEvaluator.new
    evaluator.evaluate("def double(n); n * 2; end")
    assert_equal 8, evaluator.evaluate("double(4)")
  end

  def test_reset_clears_local_variables
    evaluator = IrbEvaluator.new
    evaluator.evaluate("x = 99")
    evaluator.reset
    assert_raise(NameError) { evaluator.evaluate("x") }
  end

  def test_binding_reader_exposes_current_binding
    evaluator = IrbEvaluator.new
    evaluator.evaluate("y = 7")
    assert_includes evaluator.binding.local_variables, :y
  end

  def test_evaluation_error_propagates
    evaluator = IrbEvaluator.new
    assert_raise(NameError) { evaluator.evaluate("undefined_var_xyz") }
  end

  def test_syntax_error_propagates_as_script_error
    evaluator = IrbEvaluator.new
    assert_raise(SyntaxError) { evaluator.evaluate("def broken(") }
  end
end
