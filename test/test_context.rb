# frozen_string_literal: true

require_relative "test_helper"
require "logger"
require "stringio"
require "cclikesh/context"

class TestContext < Test::Unit::TestCase
  def setup
    @log_io = StringIO.new
    Cclikesh::Context.reset!
    Cclikesh::Context.init(logger: Logger.new(@log_io))
  end

  def test_state_set_and_get
    Cclikesh::Context.state_set(:phase, :working)
    assert_equal :working, Cclikesh::Context.state[:phase]
  end

  def test_state_returns_dup_to_prevent_external_mutation
    Cclikesh::Context.state_set(:phase, :idle)
    snapshot = Cclikesh::Context.state
    snapshot[:phase] = :hijacked
    assert_equal :idle, Cclikesh::Context.state[:phase]
  end

  def test_logger_writes_via_module
    Cclikesh::Context.logger.info("hello")
    assert_match(/hello/, @log_io.string)
  end

  def test_quit_sets_quit_flag
    refute Cclikesh::Context.quit?
    Cclikesh::Context.quit
    assert Cclikesh::Context.quit?
  end

  def test_transcript_lines_proxies_to_transcript_module
    require "cclikesh/transcript"
    Cclikesh::Transcript.clear!
    Cclikesh::Transcript.record("hello")
    assert_equal ["hello"], Cclikesh::Context.transcript_lines
  ensure
    Cclikesh::Transcript.clear!
  end
end
