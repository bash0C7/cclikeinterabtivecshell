# frozen_string_literal: true

require "test/unit"
require "stringio"
require "baslash/working_indicator"

class TestWorkingIndicatorBaslash < Test::Unit::TestCase
  def setup
    @orig_stdout = $stdout
    $stdout = StringIO.new
    Baslash::TitleBar.reset_for_test
  end

  def teardown
    Baslash::WorkingIndicator.stop  # ensure clean
    $stdout = @orig_stdout
  end

  def test_start_sets_phase_to_working
    Baslash::WorkingIndicator.start
    sleep 0.25  # let at least one tick fire
    assert_equal :working, Baslash::TitleBar.last_phase
  end

  def test_stop_resets_phase_to_ready
    Baslash::WorkingIndicator.start
    sleep 0.25
    Baslash::WorkingIndicator.stop
    assert_equal :ready, Baslash::TitleBar.last_phase
  end

  def test_double_start_is_safe
    Baslash::WorkingIndicator.start
    assert_nothing_raised { Baslash::WorkingIndicator.start }
    Baslash::WorkingIndicator.stop
  end

  def test_stop_without_start_is_safe
    assert_nothing_raised { Baslash::WorkingIndicator.stop }
  end

  def test_ctx_text_provider_is_invoked_on_start
    called = false
    provider = -> {
      called = true
      "working on something"
    }
    Baslash::WorkingIndicator.start(ctx_text_provider: provider)
    Baslash::WorkingIndicator.stop
    assert_true called, "ctx_text_provider should have been called on start"
  end
end
