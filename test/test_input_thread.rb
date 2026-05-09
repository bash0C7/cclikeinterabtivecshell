# frozen_string_literal: true

require_relative "test_helper"
require "tmpdir"
require "cclikesh/tuple_space"
require "cclikesh/input_thread"

class TestInputThread < Test::Unit::TestCase
  def test_emits_key_tuples_per_line_and_eof
    ts = Cclikesh::TupleSpace.new
    lines = ["first", "second", nil] # nil signals EOF
    idx = 0
    reader = lambda do |_prompt|
      v = lines[idx]
      idx += 1
      raise "reader called too many times" if idx > lines.size
      v
    end

    thread = Cclikesh::InputThread.start(ts, reader: reader, prompt: "> ")
    thread.join(1)

    assert_equal [:key, "first"],  ts.take([:key, "first"])
    assert_equal [:key, "second"], ts.take([:key, "second"])
    assert_equal [:key, nil],      ts.take([:key, nil])
    assert_false thread.alive?
  end

  def test_stops_when_quit_tuple_present_before_next_read
    ts = Cclikesh::TupleSpace.new
    ts.write([:cmd, :quit]) # quit already pending before thread starts

    reader_calls = 0
    reader = lambda do |_prompt|
      reader_calls += 1
      "should-not-happen"
    end

    thread = Cclikesh::InputThread.start(ts, reader: reader, prompt: "> ")
    thread.join(1)

    assert_false thread.alive?
    assert_equal 0, reader_calls, "reader should not be invoked when quit is already pending"
  end

  def test_completion_proc_forwards_to_registry_dispatch_tab
    ts = Cclikesh::TupleSpace.new
    fake_registry = Object.new
    recorded = []
    fake_registry.define_singleton_method(:dispatch_tab) do |buf, pos, ctx|
      recorded << [buf, pos, ctx]
      ["alpha", "beta"]
    end

    ctx_sentinel = :ctx_x
    proc_returned = nil
    Cclikesh::InputThread.install_completion_proc(
      registry: fake_registry, ctx: ctx_sentinel,
      apply: ->(p) { proc_returned = p }
    )
    candidates = proc_returned.call("foo")
    assert_equal ["alpha", "beta"], candidates
    assert_equal [["foo", 3, :ctx_x]], recorded
  end

  def test_completion_proc_returns_slash_names_when_buffer_starts_with_slash
    ts = Cclikesh::TupleSpace.new
    fake_registry = Object.new
    recorded_dispatch_tab = []
    fake_registry.define_singleton_method(:dispatch_tab) do |buf, pos, ctx|
      recorded_dispatch_tab << [buf, pos, ctx]
      ["should-not-see"]
    end
    fake_registry.define_singleton_method(:slash_names_starting_with) do |prefix|
      case prefix
      when "" then ["/quit", "/reset"]
      when "q" then ["/quit"]
      else []
      end
    end

    proc_returned = nil
    Cclikesh::InputThread.install_completion_proc(
      registry: fake_registry, ctx: :ctx,
      apply: ->(p) { proc_returned = p }
    )

    assert_equal ["/quit", "/reset"], proc_returned.call("/")
    assert_equal ["/quit"],           proc_returned.call("/q")
    assert_empty recorded_dispatch_tab
  end

  def test_completion_proc_routes_to_dispatch_tab_when_buffer_has_space_after_slash
    fake_registry = Object.new
    recorded = []
    fake_registry.define_singleton_method(:dispatch_tab) do |buf, pos, ctx|
      recorded << [buf, pos, ctx]
      ["arg-cand"]
    end
    fake_registry.define_singleton_method(:slash_names_starting_with) do |_|
      flunk "should not be called when buffer has space"
    end

    proc_returned = nil
    Cclikesh::InputThread.install_completion_proc(
      registry: fake_registry, ctx: :ctx_x,
      apply: ->(p) { proc_returned = p }
    )

    result = proc_returned.call("/load file")
    assert_equal ["arg-cand"], result
    assert_equal [["/load file", 10, :ctx_x]], recorded
  end

  def test_completion_proc_non_slash_buffer_routes_to_dispatch_tab
    fake_registry = Object.new
    recorded = []
    fake_registry.define_singleton_method(:dispatch_tab) do |buf, pos, ctx|
      recorded << [buf, pos, ctx]
      ["non-slash-cand"]
    end
    fake_registry.define_singleton_method(:slash_names_starting_with) do |_|
      flunk "should not be called for non-slash buffer"
    end

    proc_returned = nil
    Cclikesh::InputThread.install_completion_proc(
      registry: fake_registry, ctx: :c,
      apply: ->(p) { proc_returned = p }
    )

    result = proc_returned.call("foo")
    assert_equal ["non-slash-cand"], result
    assert_equal [["foo", 3, :c]], recorded
  end

  def test_completion_proc_at_mention_returns_file_paths
    fake_registry = Object.new
    fake_registry.define_singleton_method(:slash_names_starting_with) { |_| [] }
    fake_registry.define_singleton_method(:dispatch_tab) { |_, _, _| flunk "should not call dispatch_tab" }

    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "alpha.rb"),  "")
      File.write(File.join(dir, "beta.rb"),   "")
      File.write(File.join(dir, "other.txt"), "")

      proc_returned = nil
      Cclikesh::InputThread.install_completion_proc(
        registry: fake_registry, ctx: :ctx,
        apply: ->(p) { proc_returned = p }
      )

      Dir.chdir(dir) do
        result = proc_returned.call("@alp")
        assert_equal ["@alpha.rb"], result

        result = proc_returned.call("@")
        assert_includes result, "@alpha.rb"
        assert_includes result, "@beta.rb"
        assert_includes result, "@other.txt"

        result = proc_returned.call("hello @b")
        assert_equal ["hello @beta.rb"], result
      end
    end
  end

  def test_normalize_payload_passes_eof_through
    assert_nil Cclikesh::InputThread.normalize_payload(nil)
  end

  def test_normalize_payload_strips_trailing_newline
    assert_equal "hello", Cclikesh::InputThread.normalize_payload("hello\n")
  end

  def test_normalize_payload_collapses_backslash_continuations_to_newlines
    assert_equal "x = 1\nx + 1",
                 Cclikesh::InputThread.normalize_payload("x = 1\\\nx + 1\n")
  end

  def test_completion_proc_empty_buf_returns_prompt_suggestion
    fake_registry = Object.new
    fake_registry.define_singleton_method(:slash_names_starting_with) { |_| [] }
    fake_registry.define_singleton_method(:current_prompt_suggestion) { |_| "make me a sandwich" }
    fake_registry.define_singleton_method(:dispatch_tab) { |_, _, _| flunk "should not call dispatch_tab" }

    proc_returned = nil
    Cclikesh::InputThread.install_completion_proc(
      registry: fake_registry, ctx: :ctx,
      apply: ->(p) { proc_returned = p }
    )
    assert_equal ["make me a sandwich"], proc_returned.call("")
  end

  def test_completion_proc_empty_buf_falls_back_to_dispatch_tab_when_no_suggestion
    fake_registry = Object.new
    fake_registry.define_singleton_method(:slash_names_starting_with) { |_| [] }
    fake_registry.define_singleton_method(:current_prompt_suggestion) { |_| nil }
    recorded = []
    fake_registry.define_singleton_method(:dispatch_tab) do |b, p, c|
      recorded << [b, p, c]
      ["fallback"]
    end

    proc_returned = nil
    Cclikesh::InputThread.install_completion_proc(
      registry: fake_registry, ctx: :ctx,
      apply: ->(p) { proc_returned = p }
    )
    assert_equal ["fallback"], proc_returned.call("")
    assert_equal [["", 0, :ctx]], recorded
  end

  def test_install_completion_proc_clears_word_break_characters
    fake_registry = Object.new
    fake_registry.define_singleton_method(:slash_names_starting_with) { |_| [] }
    fake_registry.define_singleton_method(:dispatch_tab) { |_, _, _| [] }

    prev_break_chars = Reline.completer_word_break_characters
    prev_proc = Reline.completion_proc

    begin
      Reline.completer_word_break_characters = "DUMMY"
      Cclikesh::InputThread.install_completion_proc(registry: fake_registry, ctx: nil)
      assert_equal "", Reline.completer_word_break_characters
    ensure
      Reline.completer_word_break_characters = prev_break_chars
      Reline.completion_proc = prev_proc
    end
  end
end
