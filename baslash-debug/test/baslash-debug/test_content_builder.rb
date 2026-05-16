require "test/unit"
require "baslash/debug/content_builder"

class TestContentBuilder < Test::Unit::TestCase
  def test_includes_header_note
    state = { header: { note: "irb on baslash" } }
    text = Baslash::Debug::ContentBuilder.build(state)
    assert_match(/irb on baslash/, text)
  end

  def test_includes_info_bar_items
    state = { info_bar: [{ key: :elapsed, text: "1m 34s" }, { key: :tokens, text: "↓ 38b" }] }
    text = Baslash::Debug::ContentBuilder.build(state)
    assert_match(/1m 34s/, text)
    assert_match(/38b/, text)
  end

  def test_includes_status_row_segment_text
    state = { status_rows: [{ key: :clock, segments: [{ kind: :text, text: "05:31" }, { kind: :link, text: "main" }] }] }
    text = Baslash::Debug::ContentBuilder.build(state)
    assert_match(/05:31/, text)
    assert_match(/main/, text)
  end

  def test_includes_input_buffer
    state = { input: { buffer: "1223.to_i", cursor_pos: 9 } }
    text = Baslash::Debug::ContentBuilder.build(state)
    assert_match(/1223\.to_i/, text)
  end

  def test_includes_live_slot_text
    state = { live_slot: { active: true, text: "evaluating...", style: :thinking } }
    text = Baslash::Debug::ContentBuilder.build(state)
    assert_match(/evaluating/, text)
  end

  def test_marks_popup_when_active
    state = { popup: { active: true, kind: "autocomplete", candidates_count: 8 } }
    text = Baslash::Debug::ContentBuilder.build(state)
    assert_match(/popup:autocomplete:8/, text)
  end

  def test_empty_state_returns_empty_string
    assert_equal "", Baslash::Debug::ContentBuilder.build({})
  end

  def test_handles_string_keys_as_well_as_symbol_keys
    state = { "header" => { "note" => "irb on baslash" }, "info_bar" => [{ "text" => "elapsed: 1s" }] }
    text = Baslash::Debug::ContentBuilder.build(state)
    assert_match(/irb on baslash/, text)
    assert_match(/elapsed: 1s/, text)
  end
end
