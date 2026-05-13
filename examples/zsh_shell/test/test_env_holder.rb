# frozen_string_literal: true

require "test/unit"
require_relative "../env_holder"

class TestEnvHolder < Test::Unit::TestCase
  def setup
    @holder = EnvHolder.new
  end

  def test_snapshot_returns_frozen_hash
    snap = @holder.snapshot
    assert_predicate snap, :frozen?
  end

  def test_snapshot_includes_path
    assert @holder.snapshot.key?("PATH")
  end

  def test_set_adds_value
    @holder.set("CCLIKESH_TEST_KEY", "hello")
    assert_equal "hello", @holder.snapshot["CCLIKESH_TEST_KEY"]
  end

  def test_set_overwrites
    @holder.set("CCLIKESH_TEST_KEY", "a")
    @holder.set("CCLIKESH_TEST_KEY", "b")
    assert_equal "b", @holder.snapshot["CCLIKESH_TEST_KEY"]
  end

  def test_unset_removes_value
    @holder.set("CCLIKESH_TEST_KEY", "hello")
    @holder.unset("CCLIKESH_TEST_KEY")
    refute @holder.snapshot.key?("CCLIKESH_TEST_KEY")
  end

  def test_reset_restores_initial
    @holder.set("CCLIKESH_TEST_KEY", "hello")
    @holder.reset
    refute @holder.snapshot.key?("CCLIKESH_TEST_KEY")
  end

  def test_size_matches_snapshot
    assert_equal @holder.snapshot.size, @holder.size
  end
end
