# frozen_string_literal: true

require_relative "test_helper"
require "cclikesh/terminfo_overlay"

class TestTerminfoOverlay < Test::Unit::TestCase
  def setup
    @saved_env = ENV.to_h
    Cclikesh::TerminfoOverlay.reset_state_for_test
  end

  def teardown
    ENV.replace(@saved_env)
    Cclikesh::TerminfoOverlay.reset_state_for_test
  end

  def test_installed_is_false_before_install
    refute Cclikesh::TerminfoOverlay.installed?
  end

  def test_install_with_dumb_terminal_skips_and_keeps_env
    ENV["TERM"] = "dumb"
    ok = Cclikesh::TerminfoOverlay.install_if_possible
    refute ok
    refute Cclikesh::TerminfoOverlay.installed?
    assert_equal "dumb", ENV["TERM"]
  end

  def test_install_with_empty_term_skips
    ENV["TERM"] = ""
    refute Cclikesh::TerminfoOverlay.install_if_possible
    refute Cclikesh::TerminfoOverlay.installed?
    assert_equal "", ENV["TERM"]
  end

  def test_strip_smcup_rmcup_removes_both_lines
    source = <<~TI
      xterm-ghostty|ghostty|Ghostty,
        am,
        smcup=\\E[?1049h,
        rmcup=\\E[?1049l,
        cup=\\E[%i%p1%d;%p2%dH,
    TI
    out = Cclikesh::TerminfoOverlay.send(:strip_smcup_rmcup, source)
    refute_match(/smcup=/, out)
    refute_match(/rmcup=/, out)
    assert_match(/cup=/, out)  # unrelated caps survive
    assert_match(/^xterm-ghostty/, out)  # header survives
  end

  def test_strip_smcup_rmcup_handles_lines_without_either
    source = "xterm|x,\n  am,\n  cup=\\E[H,\n"
    out = Cclikesh::TerminfoOverlay.send(:strip_smcup_rmcup, source)
    assert_equal source, out
  end

  def test_strip_smcup_rmcup_is_whitespace_tolerant
    source = "x|x,\n\tsmcup=foo,\n  rmcup=bar,\n  smkx=baz,\n"
    out = Cclikesh::TerminfoOverlay.send(:strip_smcup_rmcup, source)
    refute_match(/smcup=/, out)
    refute_match(/rmcup=/, out)
    assert_match(/smkx=/, out)  # do not strip caps that merely start with "sm"
  end

  def test_read_terminfo_source_returns_nil_when_infocmp_missing
    # Simulate PATH without infocmp.
    old_path = ENV["PATH"]
    ENV["PATH"] = "/dev/null"
    src = Cclikesh::TerminfoOverlay.send(:read_terminfo_source, "xterm-256color")
    assert_nil src
  ensure
    ENV["PATH"] = old_path
  end

  def test_rename_entry_replaces_header_aliases
    source = <<~TI
      xterm-ghostty|ghostty|Ghostty,
        am,
        cup=\\E[H,
    TI
    out = Cclikesh::TerminfoOverlay.send(:rename_entry, source, "xterm-ghostty-noalt")
    assert_match(/\Axterm-ghostty-noalt\|xterm-ghostty without smcup,$/, out.lines.first.chomp)
    assert_match(/^  am,/, out)
  end

  def test_rename_entry_preserves_comments_before_header
    source = "# Reconstructed via infocmp\nxterm|x,\n  am,\n"
    out = Cclikesh::TerminfoOverlay.send(:rename_entry, source, "xterm-noalt")
    assert_match(/\A# Reconstructed/, out)
    assert_match(/^xterm-noalt\|xterm without smcup,/, out)
  end

  def test_digest_of_is_stable_for_same_input
    s = "xterm|x,\n  am,\n"
    a = Cclikesh::TerminfoOverlay.send(:digest_of, s)
    b = Cclikesh::TerminfoOverlay.send(:digest_of, s)
    assert_equal a, b
    assert_match(/\A[0-9a-f]{8,}\z/, a)
  end

  def test_digest_of_differs_for_different_input
    a = Cclikesh::TerminfoOverlay.send(:digest_of, "x|x,\n")
    b = Cclikesh::TerminfoOverlay.send(:digest_of, "y|y,\n")
    refute_equal a, b
  end
end
