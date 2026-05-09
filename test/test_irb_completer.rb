# frozen_string_literal: true

require_relative "test_helper"
require_relative "../examples/irb_shell/irb_evaluator"
require_relative "../examples/irb_shell/irb_completer"

class TestIrbCompleter < Test::Unit::TestCase
  def test_completes_local_variable_in_binding
    evaluator = IrbEvaluator.new
    evaluator.evaluate("apple = 1")
    evaluator.evaluate("apricot = 2")
    completer = IrbCompleter.new(evaluator.binding)

    candidates = completer.candidates("ap", 2)
    assert_includes candidates, "apple"
    assert_includes candidates, "apricot"
  end

  def test_completes_method_after_dot_on_local_variable
    evaluator = IrbEvaluator.new
    evaluator.evaluate("x = 42")
    completer = IrbCompleter.new(evaluator.binding)

    candidates = completer.candidates("x.to_", 5)
    assert candidates.any? { |c| c.include?("to_s") }, "expected to_s in #{candidates.inspect}"
    assert candidates.any? { |c| c.include?("to_i") }, "expected to_i in #{candidates.inspect}"
  end

  def test_completes_method_after_dot_on_string_literal
    evaluator = IrbEvaluator.new
    completer = IrbCompleter.new(evaluator.binding)

    candidates = completer.candidates(%("foo".rev), 9)
    assert candidates.any? { |c| c.include?("reverse") }, "expected reverse in #{candidates.inspect}"
  end

  def test_completes_namespaced_constant
    require "net/http"
    evaluator = IrbEvaluator.new
    completer = IrbCompleter.new(evaluator.binding)

    candidates = completer.candidates("Net::H", 6)
    assert candidates.any? { |c| c.include?("Net::HTTP") }, "expected Net::HTTP* in #{candidates.inspect}"
  end

  def test_completes_constant
    evaluator = IrbEvaluator.new
    completer = IrbCompleter.new(evaluator.binding)

    candidates = completer.candidates("Stri", 4)
    assert_includes candidates, "String"
  end

  def test_completes_kernel_method
    evaluator = IrbEvaluator.new
    completer = IrbCompleter.new(evaluator.binding)

    candidates = completer.candidates("put", 3)
    assert_includes candidates, "puts"
  end

  def test_returns_empty_when_no_word_at_pos
    evaluator = IrbEvaluator.new
    completer = IrbCompleter.new(evaluator.binding)

    assert_empty completer.candidates("", 0)
    assert_empty completer.candidates("   ", 3)
  end

  def test_handles_pos_in_middle_of_buffer
    evaluator = IrbEvaluator.new
    evaluator.evaluate("foo = 1")
    completer = IrbCompleter.new(evaluator.binding)

    candidates = completer.candidates("fo bar", 2)
    assert_includes candidates, "foo"
  end

  def test_returns_unique_candidates
    evaluator = IrbEvaluator.new
    completer = IrbCompleter.new(evaluator.binding)

    candidates = completer.candidates("p", 1)
    assert_equal candidates.uniq, candidates
  end
end
