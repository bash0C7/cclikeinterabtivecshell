# frozen_string_literal: true

require_relative "test_helper"
require "logger"
require "stringio"
require "baslash/context"

class TestContextBaslash < Test::Unit::TestCase
  def setup
    @log_io = StringIO.new
    Baslash::Context.reset!
    Baslash::Context.init(logger: Logger.new(@log_io))
  end

  def test_state_set_and_get
    Baslash::Context.state_set(:phase, :working)
    assert_equal :working, Baslash::Context.state[:phase]
  end

  def test_state_returns_dup_to_prevent_external_mutation
    Baslash::Context.state_set(:phase, :idle)
    snapshot = Baslash::Context.state
    snapshot[:phase] = :hijacked
    assert_equal :idle, Baslash::Context.state[:phase]
  end

  def test_logger_writes_via_module
    Baslash::Context.logger.info("hello")
    assert_match(/hello/, @log_io.string)
  end

  def test_quit_sets_quit_flag
    refute Baslash::Context.quit?
    Baslash::Context.quit
    assert Baslash::Context.quit?
  end

  def test_transcript_lines_proxies_to_transcript_module
    require "baslash/transcript"
    Baslash::Transcript.clear!
    Baslash::Transcript.record("hello")
    assert_equal ["hello"], Baslash::Context.transcript_lines
  ensure
    Baslash::Transcript.clear!
  end
end
