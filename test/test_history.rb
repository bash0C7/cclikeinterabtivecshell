# frozen_string_literal: true

require_relative "test_helper"
require "tmpdir"
require "cclikesh/history"

class TestHistory < Test::Unit::TestCase
  def test_path_for_is_under_hist_dir_and_includes_cwd_hash
    path = Cclikesh::History.path_for("/some/work/dir")
    assert path.start_with?(Cclikesh::History::HIST_DIR), path
    assert_match(/[0-9a-f]{16}\.txt\z/, path)
  end

  def test_path_for_is_stable_for_same_cwd
    a = Cclikesh::History.path_for("/x/y")
    b = Cclikesh::History.path_for("/x/y")
    assert_equal a, b
  end

  def test_path_for_differs_per_cwd
    a = Cclikesh::History.path_for("/x/y")
    b = Cclikesh::History.path_for("/x/z")
    refute_equal a, b
  end

  def test_load_missing_returns_empty
    assert_equal [], Cclikesh::History.load("/nonexistent/no/history/file.txt")
  end

  def test_save_then_load_roundtrip_simple
    Dir.mktmpdir do |dir|
      path = File.join(dir, "subdir", "h.txt")
      Cclikesh::History.save(path, ["hello", "world"])
      assert_equal ["hello", "world"], Cclikesh::History.load(path)
    end
  end

  def test_save_then_load_preserves_embedded_newlines
    Dir.mktmpdir do |dir|
      path = File.join(dir, "h.txt")
      entry = "x = 1\nx + 1"
      Cclikesh::History.save(path, [entry])
      assert_equal [entry], Cclikesh::History.load(path)
    end
  end

  def test_save_then_load_preserves_literal_backslash_n
    Dir.mktmpdir do |dir|
      path = File.join(dir, "h.txt")
      entry = "echo hello\\nworld"  # literal "\n" in source string
      Cclikesh::History.save(path, [entry])
      assert_equal [entry], Cclikesh::History.load(path)
    end
  end

  def test_encode_decode_roundtrip_for_various_strings
    [
      "plain",
      "with\nnewline",
      "with\\backslash",
      "mixed\\with\nstuff",
      "trailing\\",
      "",
    ].each do |s|
      decoded = Cclikesh::History.decode(Cclikesh::History.encode(s))
      assert_equal s, decoded, "roundtrip failed for #{s.inspect}"
    end
  end
end
