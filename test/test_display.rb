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

  def test_open_live_returns_live_slot
    ts = Cclikesh::TupleSpace.new
    d = Cclikesh::Display.new(ts)
    slot = d.open_live(style: :thinking)
    assert_kind_of Cclikesh::LiveSlot, slot
    assert_equal :thinking, slot.style
    assert_equal true, slot.open?
  end

  def test_open_live_writes_live_open_tuple
    ts = Cclikesh::TupleSpace.new
    d = Cclikesh::Display.new(ts)
    slot = d.open_live(style: :thinking)
    tuple = ts.take([:render, :live_open, slot.id, nil], 0)
    assert_equal [:render, :live_open, slot.id, { style: :thinking }], tuple
  end

  def test_open_live_assigns_unique_ids
    ts = Cclikesh::TupleSpace.new
    d = Cclikesh::Display.new(ts)
    s1 = d.open_live
    # s2 open triggers auto-commit of s1
    s2 = d.open_live
    refute_equal s1.id, s2.id
  end

  def test_second_open_live_auto_commits_first
    ts = Cclikesh::TupleSpace.new
    d = Cclikesh::Display.new(ts)
    s1 = d.open_live
    s2 = d.open_live
    assert_equal false, s1.open?
    assert_equal true, s2.open?
  end

  def test_open_live_block_form_yields_slot_and_commits
    ts = Cclikesh::TupleSpace.new
    d = Cclikesh::Display.new(ts)

    captured = nil
    result = d.open_live(style: :thinking) do |slot|
      captured = slot
      slot.update("...")
    end

    assert_kind_of Cclikesh::LiveSlot, captured
    assert_equal false, captured.open?  # auto-committed
    assert_equal captured, result        # returned slot
  end

  def test_open_live_block_form_discards_on_exception
    ts = Cclikesh::TupleSpace.new
    d = Cclikesh::Display.new(ts)

    raised = nil
    captured = nil
    begin
      d.open_live do |slot|
        captured = slot
        raise "boom"
      end
    rescue => e
      raised = e
    end

    assert_equal "boom", raised.message
    assert_equal false, captured.open?
    # discard tuple was emitted, not commit
    discard = ts.take([:render, :live_discard, captured.id], 0)
    assert_equal [:render, :live_discard, captured.id], discard
  end

  def test_open_live_block_form_discards_on_non_standard_error
    ts = Cclikesh::TupleSpace.new
    d = Cclikesh::Display.new(ts)

    captured = nil
    raised = nil
    begin
      d.open_live do |slot|
        captured = slot
        raise Interrupt, "ctrl-c"
      end
    rescue Interrupt => e
      raised = e
    end

    assert_kind_of Interrupt, raised
    assert_equal false, captured.open?
    discard = ts.take([:render, :live_discard, captured.id], 0)
    assert_equal [:render, :live_discard, captured.id], discard
  end
end
