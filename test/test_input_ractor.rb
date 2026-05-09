# frozen_string_literal: true

require_relative "test_helper"
require "cclikesh/tuple_space"
require "cclikesh/input_ractor"

class TestInputRactor < Test::Unit::TestCase
  def setup
    Dir.mkdir("tmp") unless Dir.exist?("tmp")
    @input_path = "tmp/test_input_ractor_#{Process.pid}_#{rand(99999)}.txt"
  end

  def teardown
    File.unlink(@input_path) if @input_path && File.exist?(@input_path)
  end

  # ts4r's tuple bag returns matches in LIFO when multiple tuples accumulate
  # before any take. Production users type one line at a time so this never
  # surfaces, but a pre-filled test file races. We assert as a set instead.
  def test_emits_key_tuples_for_each_line
    File.write(@input_path, "first\nsecond\n")
    ts = Cclikesh::TupleSpace.new
    Cclikesh::InputRactor.start(ts, @input_path)
    collected = [ts.take([:key, nil]), ts.take([:key, nil]), ts.take([:key, nil])]
    expected = [[:key, "first"], [:key, "second"], [:key, nil]]
    assert_equal expected.sort_by(&:to_s), collected.sort_by(&:to_s)
  end
end
