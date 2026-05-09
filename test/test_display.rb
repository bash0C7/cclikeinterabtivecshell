# frozen_string_literal: true

require_relative "test_helper"
require "cclikesh/tuple_space"
require "cclikesh/display"

class TestDisplay < Test::Unit::TestCase
  def test_append_writes_render_tuple
    ts = Cclikesh::TupleSpace.new
    d = Cclikesh::Display.new(ts)
    d.append("hello")
    assert_equal [:render, :display_append, "hello", {}], ts.take([:render, :display_append, nil, nil])
  end

  def test_append_with_style_and_prompt
    ts = Cclikesh::TupleSpace.new
    d = Cclikesh::Display.new(ts)
    d.append("=> 42", style: :result)
    d.append("x = 1", prompt: "irb> ")
    assert_equal [:render, :display_append, "=> 42", {style: :result}],
                 ts.take([:render, :display_append, "=> 42", nil])
    assert_equal [:render, :display_append, "x = 1", {prompt: "irb> "}],
                 ts.take([:render, :display_append, "x = 1", nil])
  end
end
