# frozen_string_literal: true

require "stringio"
require_relative "test_helper"
require "cclikesh/tuple_space"
require "cclikesh/renderer"

class TestRenderer < Test::Unit::TestCase
  def test_processes_one_pending_append
    ts = Cclikesh::TupleSpace.new
    out = StringIO.new
    r = Cclikesh::Renderer.new(ts, out)
    ts.write([:render, :display_append, "hello", {}])
    r.render_pending
    assert_equal "hello\n", out.string
  end

  def test_processes_multiple_pending_appends_in_order
    ts = Cclikesh::TupleSpace.new
    out = StringIO.new
    r = Cclikesh::Renderer.new(ts, out)
    ts.write([:render, :display_append, "first", {}])
    ts.write([:render, :display_append, "second", {}])
    r.render_pending
    assert_equal "first\nsecond\n", out.string
  end

  def test_render_pending_with_no_tuples_does_not_block
    ts = Cclikesh::TupleSpace.new
    out = StringIO.new
    r = Cclikesh::Renderer.new(ts, out)
    r.render_pending
    assert_equal "", out.string
  end

  def test_appends_prompt_prefix_when_present
    ts = Cclikesh::TupleSpace.new
    out = StringIO.new
    r = Cclikesh::Renderer.new(ts, out)
    ts.write([:render, :display_append, "x = 1", {prompt: "irb> "}])
    r.render_pending
    assert_equal "irb> x = 1\n", out.string
  end
end
