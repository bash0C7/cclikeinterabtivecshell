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
    assert_match(/\A[0-9a-f]{16}\z/, a)
  end

  def test_digest_of_differs_for_different_input
    a = Cclikesh::TerminfoOverlay.send(:digest_of, "x|x,\n")
    b = Cclikesh::TerminfoOverlay.send(:digest_of, "y|y,\n")
    refute_equal a, b
  end

  def test_cache_root_respects_xdg_cache_home
    ENV["XDG_CACHE_HOME"] = "/tmp/xdg-cache-test"
    root = Cclikesh::TerminfoOverlay.send(:cache_root)
    assert_equal "/tmp/xdg-cache-test/cclikesh/terminfo", root
  end

  def test_cache_root_falls_back_to_home_dot_cache
    ENV.delete("XDG_CACHE_HOME")
    root = Cclikesh::TerminfoOverlay.send(:cache_root)
    assert_match %r{/\.cache/cclikesh/terminfo\z}, root
    assert root.start_with?(Dir.home)
  end

  def test_cache_dir_for_includes_term_and_digest
    ENV["XDG_CACHE_HOME"] = "/tmp/xdg-cache-test"
    dir = Cclikesh::TerminfoOverlay.send(:cache_dir_for, "xterm-ghostty", "deadbeefdeadbeef")
    assert_equal "/tmp/xdg-cache-test/cclikesh/terminfo/xterm-ghostty-noalt-deadbeefdeadbeef", dir
  end

  def test_compile_terminfo_produces_loadable_entry
    require "tmpdir"
    Dir.mktmpdir do |dir|
      src_path = File.join(dir, "src.ti")
      # Use a real entry derived from the test runner's TERM so the
      # tic on this machine accepts it.
      term = ENV["TERM"] || "xterm-256color"
      raw = Cclikesh::TerminfoOverlay.send(:read_terminfo_source, term)
      omit "infocmp unavailable" if raw.nil?
      stripped = Cclikesh::TerminfoOverlay.send(:strip_smcup_rmcup, raw)
      renamed  = Cclikesh::TerminfoOverlay.send(:rename_entry, stripped, "cclikeshtest-noalt")
      File.write(src_path, renamed)

      out_dir = File.join(dir, "ti-out")
      Dir.mkdir(out_dir)
      ok = Cclikesh::TerminfoOverlay.send(:compile_terminfo, src_path, out_dir)
      assert ok, "compile_terminfo returned false"

      # Verify infocmp can read the compiled entry back, and that
      # smcup/rmcup are absent.
      verify = `TERMINFO_DIRS=#{out_dir} infocmp -1 cclikeshtest-noalt 2>/dev/null`
      refute_match(/smcup=/, verify)
      refute_match(/rmcup=/, verify)
    end
  end
end
