# frozen_string_literal: true

require_relative "test_helper"
require "cclikesh/info_bar"

class TestInfoBar < Test::Unit::TestCase
  def test_returns_empty_when_no_label_no_segments
    out = Cclikesh::InfoBar.compose(spinner_frame: nil, spinner_label: nil, segments: [])
    assert_equal "", out
  end

  def test_renders_spinner_frame_and_label
    out = Cclikesh::InfoBar.compose(spinner_frame: "✻", spinner_label: "Roosting", segments: [])
    assert_match(/✻/, out)
    assert_match(/Roosting/, out)
  end

  def test_renders_label_only_when_no_frame
    out = Cclikesh::InfoBar.compose(spinner_frame: nil, spinner_label: "Awaiting", segments: [])
    refute_match(/✻/, out)
    assert_match(/Awaiting/, out)
  end

  def test_joins_segments_with_dot_separator
    out = Cclikesh::InfoBar.compose(spinner_frame: nil, spinner_label: nil, segments: ["3s", "↓ 1k"])
    assert_match(/3s/, out)
    assert_match(/↓ 1k/, out)
    assert_match(/·/, out)
    assert_match(/\(.+\)/, out)
  end

  def test_label_and_segments_appear_together
    out = Cclikesh::InfoBar.compose(
      spinner_frame: "✻",
      spinner_label: "Roosting",
      segments: ["3s", "↓ 1k"]
    )
    assert_match(/✻.*Roosting/, out)
    assert_match(/Roosting.*\(.*3s · ↓ 1k.*\)/, out)
  end

  def test_renders_dim_ansi_for_segments
    out = Cclikesh::InfoBar.compose(spinner_frame: nil, spinner_label: nil, segments: ["3s"])
    assert_match(/\e\[2m/, out)
    assert_match(/\e\[0m/, out)
  end
end
