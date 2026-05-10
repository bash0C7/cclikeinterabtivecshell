require "test/unit"
require "reline"
require "cclikesh/builder"
require "cclikesh/runner"

class TestOnTabWiring < Test::Unit::TestCase
  def teardown
    Reline.completion_proc = nil
  end

  def test_on_tab_handler_is_set_as_reline_completion_proc
    builder = Cclikesh::Builder.new
    builder.on_tab { |word| ["#{word}_one", "#{word}_two"] }

    Cclikesh::Runner.send(:install_completion, builder)
    proc_set = Reline.completion_proc
    refute_nil proc_set, "Reline.completion_proc should be set when on_tab is registered"
    assert_equal ["foo_one", "foo_two"], proc_set.call("foo")
  end

  def test_no_on_tab_leaves_completion_proc_alone
    Reline.completion_proc = nil
    builder = Cclikesh::Builder.new
    Cclikesh::Runner.send(:install_completion, builder)
    assert_nil Reline.completion_proc, "no-op when on_tab unset"
  end
end
