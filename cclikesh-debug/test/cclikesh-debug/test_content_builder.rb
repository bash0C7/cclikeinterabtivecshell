require "test/unit"
require "cclikesh/debug/content_builder"

class TestContentBuilder < Test::Unit::TestCase
  def test_includes_header_note
    state = { header: { note: "irb on cclikesh" } }
    text = Cclikesh::Debug::ContentBuilder.build(state)
    assert_match(/irb on cclikesh/, text)
  end

  def test_includes_info_bar_items
    state = { info_bar: [{ key: :elapsed, text: "1m 34s" }, { key: :tokens, text: "↓ 38b" }] }
    text = Cclikesh::Debug::ContentBuilder.build(state)
    assert_match(/1m 34s/, text)
    assert_match(/38b/, text)
  end

  def test_includes_status_row_segment_text
    state = { status_rows: [{ key: :clock, segments: [{ kind: :text, text: "05:31" }, { kind: :link, text: "main" }] }] }
    text = Cclikesh::Debug::ContentBuilder.build(state)
    assert_match(/05:31/, text)
    assert_match(/main/, text)
  end

  def test_includes_input_buffer
    state = { input: { buffer: "1223.to_i", cursor_pos: 9 } }
    text = Cclikesh::Debug::ContentBuilder.build(state)
    assert_match(/1223\.to_i/, text)
  end

  def test_includes_live_slot_text
    state = { live_slot: { active: true, text: "evaluating...", style: :thinking } }
    text = Cclikesh::Debug::ContentBuilder.build(state)
    assert_match(/evaluating/, text)
  end

  def test_marks_popup_when_active
    state = { popup: { active: true, kind: "autocomplete", candidates_count: 8 } }
    text = Cclikesh::Debug::ContentBuilder.build(state)
    assert_match(/popup:autocomplete:8/, text)
  end

  def test_empty_state_returns_empty_string
    assert_equal "", Cclikesh::Debug::ContentBuilder.build({})
  end

  def test_handles_string_keys_as_well_as_symbol_keys
    state = { "header" => { "note" => "irb on cclikesh" }, "info_bar" => [{ "text" => "elapsed: 1s" }] }
    text = Cclikesh::Debug::ContentBuilder.build(state)
    assert_match(/irb on cclikesh/, text)
    assert_match(/elapsed: 1s/, text)
  end
end
