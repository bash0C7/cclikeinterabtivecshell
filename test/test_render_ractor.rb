# frozen_string_literal: true

require_relative "test_helper"
require "cclikesh/tuple_space"
require "cclikesh/render_ractor"

class TestRenderRactor < Test::Unit::TestCase
  def setup
    Dir.mkdir("tmp") unless Dir.exist?("tmp")
    @out_path = "tmp/test_render_ractor_#{Process.pid}_#{rand(99999)}.txt"
    File.write(@out_path, "")
  end

  def teardown
    File.unlink(@out_path) if @out_path && File.exist?(@out_path)
  end

  def test_emits_rendered_after_processing_appends
    ts = Cclikesh::TupleSpace.new
    ractor = Cclikesh::RenderRactor.start(ts, @out_path, tick_interval: 0.02)
    ts.write([:render, :display_append, "hi", {}])
    _, frame_id = ts.take([:rendered, nil])
    assert_kind_of Integer, frame_id
    ts.write([:cmd, :quit])
    ractor.value rescue nil
    assert_equal "hi\n", File.read(@out_path)
  end

  def test_processes_multiple_appends_in_order
    ts = Cclikesh::TupleSpace.new
    ractor = Cclikesh::RenderRactor.start(ts, @out_path, tick_interval: 0.02)
    ts.write([:render, :display_append, "a", {}])
    ts.write([:render, :display_append, "b", {}])
    deadline = Time.now + 1.0
    until File.read(@out_path).include?("b\n")
      flunk "render_ractor did not process both appends within 1s" if Time.now > deadline
      ts.take([:rendered, nil])
    end
    ts.write([:cmd, :quit])
    ractor.value rescue nil
    assert_equal "a\nb\n", File.read(@out_path)
  end
end
