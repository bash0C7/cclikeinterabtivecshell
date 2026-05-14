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
  end
end
