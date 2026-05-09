# frozen_string_literal: true

require_relative "test_helper"
require "cclikesh/builder"
require "cclikesh/handler_registry"
require "cclikesh/forking"

class TestForking < Test::Unit::TestCase
  def test_child_can_call_registry_via_drb_and_handler_runs_in_parent
    parent_pid = Process.pid
    sentinel = "/tmp/cclikesh-fork-test-#{parent_pid}.txt"
    File.delete(sentinel) if File.exist?(sentinel)

    builder = Cclikesh::Builder.new
    builder.on_submit do |line, _ctx|
      File.write(sentinel, "got:#{line}")
    end
    registry = Cclikesh::HandlerRegistry.new(builder)

    Cclikesh::Forking.run(registry) do |handlers_uri|
      require "drb/drb"
      require "drb/unix"
      DRb.start_service
      remote = DRbObject.new_with_uri(handlers_uri)
      remote.dispatch_submit("hello-from-child", nil)
      DRb.stop_service
      exit 0
    end

    assert_path_exist sentinel
    assert_equal "got:hello-from-child", File.read(sentinel)
  ensure
    File.delete(sentinel) if sentinel && File.exist?(sentinel)
  end
end
