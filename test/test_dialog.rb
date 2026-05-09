# frozen_string_literal: true

require_relative "test_helper"
require "cclikesh/dialog"
require "cclikesh/display"
require "cclikesh/tuple_space"

class TestDialog < Test::Unit::TestCase
  def test_show_emits_top_content_lines_and_bottom
    ts = Cclikesh::TupleSpace.new
    display = Cclikesh::Display.new(ts)
    dialog = Cclikesh::Dialog.new(display)
    dialog.show("alpha\nbeta")

    texts = drain_display_tuples(ts).map { |t| t[2] }
    assert_equal 4, texts.size
    assert texts.any? { |t| t.include?("┌") }, "expected top border, got: #{texts.inspect}"
    assert texts.any? { |t| t.include?("alpha") }, "expected alpha line, got: #{texts.inspect}"
    assert texts.any? { |t| t.include?("beta") }, "expected beta line, got: #{texts.inspect}"
    assert texts.any? { |t| t.include?("└") }, "expected bottom border, got: #{texts.inspect}"
  end

  def test_show_with_style_passes_style_to_content_lines
    ts = Cclikesh::TupleSpace.new
    display = Cclikesh::Display.new(ts)
    dialog = Cclikesh::Dialog.new(display)
    dialog.show("hello", style: :result)

    tuples = drain_display_tuples(ts)
    content_tuples = tuples.select { |t| t[2].include?("hello") }
    assert_equal 1, content_tuples.size
    assert_equal :result, content_tuples[0][3][:style]
  end

  def test_close_is_noop
    ts = Cclikesh::TupleSpace.new
    display = Cclikesh::Display.new(ts)
    dialog = Cclikesh::Dialog.new(display)
    dialog.close
    assert_raise(Rinda::RequestExpiredError) do
      ts.take([:render, :display_append, nil, nil], 0)
    end
  end

  private

  def drain_display_tuples(ts)
    out = []
    loop { out << ts.take([:render, :display_append, nil, nil], 0) }
  rescue Rinda::RequestExpiredError
    out
  end
end
