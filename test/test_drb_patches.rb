# frozen_string_literal: true

require_relative "test_helper"
require "drb/drb"
require "drb/unix"
require "cclikesh/drb_patches"

class TestDRbPatches < Test::Unit::TestCase
  def test_drb_object_does_not_inherit_kernel_display
    refute DRb::DRbObject.method_defined?(:display),
           "DRbObject#display must be undef'd so remote dispatch routes via method_missing"
  end

  def test_remote_display_method_routes_to_real_object
    server_class = Class.new do
      include DRb::DRbUndumped
      def display
        "real-display-result"
      end
    end

    uri = "drbunix:///tmp/cclikesh-drb-patches-test-#{Process.pid}.sock"
    File.delete(uri.sub(%r{\Adrbunix://}, "")) rescue nil

    DRb.start_service(uri, server_class.new)

    sentinel = "/tmp/cclikesh-drb-patches-test-out-#{Process.pid}.txt"
    File.delete(sentinel) if File.exist?(sentinel)

    pid = fork do
      DRb.stop_service
      DRb.start_service
      remote = DRbObject.new_with_uri(uri)
      File.write(sentinel, remote.display.to_s)
      DRb.stop_service
      exit 0
    end
    Process.wait(pid)
    DRb.stop_service

    assert_equal "real-display-result", File.read(sentinel)
  ensure
    File.delete(sentinel) if sentinel && File.exist?(sentinel)
  end
end
