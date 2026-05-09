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

  class FakeRegistry
    def initialize(map); @map = map; end
    def style_definition(name); @map[name&.to_sym]; end
  end

  def test_render_pending_uses_custom_style_from_registry
    ts = Cclikesh::TupleSpace.new
    out = StringIO.new
    reg = FakeRegistry.new(my_warn: { fg: :yellow, bold: true })
    r = Cclikesh::Renderer.new(ts, out, registry: reg)

    ts.write([:render, :display_append, "warn!", { style: :my_warn }])
    r.render_pending

    assert_equal "\e[1;33mwarn!\e[0m\n", out.string
  end

  def test_render_pending_unknown_custom_style_falls_back_to_plain
    ts = Cclikesh::TupleSpace.new
    out = StringIO.new
    reg = FakeRegistry.new({})
    r = Cclikesh::Renderer.new(ts, out, registry: reg)

    ts.write([:render, :display_append, "x", { style: :nope }])
    r.render_pending

    assert_equal "x\n", out.string
  end

  def test_render_pending_live_update_writes_inplace_ansi
    ts = Cclikesh::TupleSpace.new
    out = StringIO.new
    r = Cclikesh::Renderer.new(ts, out)

    ts.write([:render, :live_open, 1, { style: :thinking }])
    ts.write([:render, :live_update, 1, "step 1"])
    r.render_pending

    assert_equal "\r\e[2K\e[35mstep 1\e[0m", out.string
  end

  def test_render_pending_multiple_live_updates_overwrite_same_line
    ts = Cclikesh::TupleSpace.new
    out = StringIO.new
    r = Cclikesh::Renderer.new(ts, out)

    ts.write([:render, :live_open, 1, { style: nil }])
    ts.write([:render, :live_update, 1, "a"])
    ts.write([:render, :live_update, 1, "bb"])
    r.render_pending

    # both updates render: \r\e[2K + text, sequentially
    assert_equal "\r\e[2Ka\r\e[2Kbb", out.string
  end

  def test_render_pending_live_update_for_inactive_slot_is_noop
    ts = Cclikesh::TupleSpace.new
    out = StringIO.new
    r = Cclikesh::Renderer.new(ts, out)

    # no live_open written first
    ts.write([:render, :live_update, 99, "stray"])
    r.render_pending

    assert_equal "", out.string
  end

  def test_render_pending_live_commit_with_nil_uses_last_text_and_newline
    ts = Cclikesh::TupleSpace.new
    out = StringIO.new
    r = Cclikesh::Renderer.new(ts, out)

    ts.write([:render, :live_open, 1, { style: nil }])
    ts.write([:render, :live_update, 1, "final"])
    ts.write([:render, :live_commit, 1, nil])
    r.render_pending

    assert_equal "\r\e[2Kfinal\r\e[2Kfinal\n", out.string
  end

  def test_render_pending_live_commit_with_final_overrides
    ts = Cclikesh::TupleSpace.new
    out = StringIO.new
    r = Cclikesh::Renderer.new(ts, out)

    ts.write([:render, :live_open, 1, { style: nil }])
    ts.write([:render, :live_update, 1, "tmp"])
    ts.write([:render, :live_commit, 1, "DONE"])
    r.render_pending

    assert_equal "\r\e[2Ktmp\r\e[2KDONE\n", out.string
  end

  def test_render_pending_live_discard_clears_line_no_newline
    ts = Cclikesh::TupleSpace.new
    out = StringIO.new
    r = Cclikesh::Renderer.new(ts, out)

    ts.write([:render, :live_open, 1, { style: nil }])
    ts.write([:render, :live_update, 1, "abc"])
    ts.write([:render, :live_discard, 1])
    r.render_pending

    assert_equal "\r\e[2Kabc\r\e[2K", out.string
  end

  def test_render_pending_live_commit_clears_state_so_subsequent_update_ignored
    ts = Cclikesh::TupleSpace.new
    out = StringIO.new
    r = Cclikesh::Renderer.new(ts, out)

    ts.write([:render, :live_open, 1, { style: nil }])
    ts.write([:render, :live_update, 1, "a"])
    ts.write([:render, :live_commit, 1, nil])
    ts.write([:render, :live_update, 1, "ignored"])
    r.render_pending

    assert_equal "\r\e[2Ka\r\e[2Ka\n", out.string
  end

  def test_render_pending_history_during_live_clears_redraws_live
    ts = Cclikesh::TupleSpace.new
    out = StringIO.new
    r = Cclikesh::Renderer.new(ts, out)

    ts.write([:render, :live_open, 1, { style: nil }])
    ts.write([:render, :live_update, 1, "live"])
    ts.write([:render, :display_append, "history", {}])
    r.render_pending

    # live update writes "\r\e[2Klive"
    # history append: clear live ("\r\e[2K") + write "history\n" + redraw live ("\r\e[2Klive")
    expected =
      "\r\e[2Klive" +
      "\r\e[2K" + "history\n" +
      "\r\e[2Klive"
    assert_equal expected, out.string
  end

  def test_render_pending_history_when_no_live_active_unchanged
    ts = Cclikesh::TupleSpace.new
    out = StringIO.new
    r = Cclikesh::Renderer.new(ts, out)

    ts.write([:render, :display_append, "x", {}])
    r.render_pending

    assert_equal "x\n", out.string
  end
end
