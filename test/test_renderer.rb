# frozen_string_literal: true

require_relative "test_helper"
require "stringio"
require "cclikesh/tuple_space"
require "cclikesh/renderer"

class TestRenderer < Test::Unit::TestCase
  def test_render_pending_drains_display_append_tuples
    ts = Cclikesh::TupleSpace.new
    out = StringIO.new
    r = Cclikesh::Renderer.new(ts, out)

    ts.write([:render, :display_append, "first", {}])
    ts.write([:render, :display_append, "second", {}])

    r.render_pending

    assert_equal "first\nsecond\n", out.string
  end

  def test_render_pending_with_empty_queue_is_noop
    ts = Cclikesh::TupleSpace.new
    out = StringIO.new
    r = Cclikesh::Renderer.new(ts, out)

    r.render_pending

    assert_equal "", out.string
  end

  def test_render_pending_with_prompt_prefix
    ts = Cclikesh::TupleSpace.new
    out = StringIO.new
    r = Cclikesh::Renderer.new(ts, out)

    ts.write([:render, :display_append, "msg", { prompt: "> " }])

    r.render_pending

    assert_equal "> msg\n", out.string
  end

  def test_render_pending_applies_builtin_result_style
    ts = Cclikesh::TupleSpace.new
    out = StringIO.new
    r = Cclikesh::Renderer.new(ts, out)

    ts.write([:render, :display_append, "ok", { style: :result }])
    r.render_pending

    assert_equal "\e[32mok\e[0m\n", out.string
  end

  def test_render_pending_applies_error_style
    ts = Cclikesh::TupleSpace.new
    out = StringIO.new
    r = Cclikesh::Renderer.new(ts, out)

    ts.write([:render, :display_append, "boom", { style: :error }])
    r.render_pending

    assert_equal "\e[31mboom\e[0m\n", out.string
  end

  def test_render_pending_no_style_returns_plain_text
    ts = Cclikesh::TupleSpace.new
    out = StringIO.new
    r = Cclikesh::Renderer.new(ts, out)

    ts.write([:render, :display_append, "plain", {}])
    r.render_pending

    assert_equal "plain\n", out.string
  end

  def test_render_pending_style_with_prompt_wraps_text_only
    ts = Cclikesh::TupleSpace.new
    out = StringIO.new
    r = Cclikesh::Renderer.new(ts, out)

    ts.write([:render, :display_append, "msg", { style: :result, prompt: ">> " }])
    r.render_pending

    assert_equal ">> \e[32mmsg\e[0m\n", out.string
  end
end
