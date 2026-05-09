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
    # drain s1 open + auto-commit (s2 open will trigger commit)
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
end
