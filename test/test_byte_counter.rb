# frozen_string_literal: true

require_relative "test_helper"
require_relative "../examples/irb_shell/byte_counter"

class TestByteCounter < Test::Unit::TestCase
  def test_starts_at_zero
    counter = ByteCounter.new
    assert_equal 0, counter.bytes
  end

  def test_add_accumulates
    counter = ByteCounter.new
    counter.add(100)
    counter.add(50)
    assert_equal 150, counter.bytes
  end

  def test_reset_clears_total
    counter = ByteCounter.new
    counter.add(500)
    counter.reset
    assert_equal 0, counter.bytes
  end

  def test_human_under_1k_uses_b_suffix
    counter = ByteCounter.new
    counter.add(512)
    assert_equal "512b", counter.human
  end

  def test_human_kilobytes
    counter = ByteCounter.new
    counter.add(2048)
    assert_equal "2.0kb", counter.human
  end

  def test_human_megabytes
    counter = ByteCounter.new
    counter.add(2 * 1024 * 1024 + 100 * 1024)
    assert_equal "2.1mb", counter.human
  end
end
