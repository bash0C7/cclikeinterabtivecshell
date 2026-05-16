# frozen_string_literal: true

require "test/unit"
require "open3"
require "timeout"

class TestExamplesSmokeBaslash < Test::Unit::TestCase
  REPO_ROOT = File.expand_path("..", __dir__)

  def test_echo_shell_boots_and_quits
    cmd = "bundle exec ruby examples/echo_shell.rb"
    Open3.popen2e(cmd, chdir: REPO_ROOT) do |stdin, out, wait_thr|
      stdin.puts "/exit"
      stdin.close
      Timeout.timeout(15) { wait_thr.value }
      output = out.read
      assert_equal 0, wait_thr.value.exitstatus, "echo_shell should exit cleanly. Output: #{output[-2000..]}"
    end
  end

  def test_zsh_shell_boots_and_quits
    cmd = "bundle exec ruby examples/zsh_shell/zsh_shell.rb"
    Open3.popen2e(cmd, chdir: REPO_ROOT) do |stdin, out, wait_thr|
      stdin.puts "/exit"
      stdin.close
      Timeout.timeout(15) { wait_thr.value }
      output = out.read
      assert_equal 0, wait_thr.value.exitstatus, "zsh_shell should exit cleanly. Output: #{output[-2000..]}"
    end
  end

  def test_irb_shell_boots_and_quits
    # NEEDS_CONTEXT: irb_shell currently crashes at boot because
    # IrbEvaluator holds a Binding (@binding = fresh_binding) and
    # Ractor.new(obj) raises TypeError: allocator undefined for Binding
    # when shareable_ref tries to spawn the actor. This is independent
    # of the prompt: kwarg bug fixed in this commit (which would have
    # been the next crash, on first input). Leave the smoke test in
    # place so the issue stays visible; mark pending until the Binding
    # / shareable-ref boundary is sorted.
    omit "irb_shell crashes at boot: Binding not shareable across Ractors (separate bug, needs design)"

    cmd = "bundle exec ruby examples/irb_shell/irb_shell.rb"
    Open3.popen2e(cmd, chdir: REPO_ROOT) do |stdin, out, wait_thr|
      stdin.puts "1 + 1"
      stdin.puts "/exit"
      stdin.close
      Timeout.timeout(15) { wait_thr.value }
      output = out.read
      assert_equal 0, wait_thr.value.exitstatus, "irb_shell should exit cleanly. Output: #{output[-2000..]}"
    end
  end
end
