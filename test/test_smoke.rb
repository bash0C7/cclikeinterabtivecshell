# frozen_string_literal: true

require_relative "test_helper"
require "pty"
require "timeout"

class TestSmoke < Test::Unit::TestCase
  ROOT = File.expand_path("..", __dir__)

  def test_echo_shell_boots_and_quits_cleanly
    pid = nil
    Timeout.timeout(15) do
      master, slave = PTY.open
      pid = spawn(
        "bundle", "exec", "ruby", "-Ilib", File.join(ROOT, "examples/echo_shell.rb"),
        in: slave, out: slave, err: slave, chdir: ROOT
      )
      slave.close
      sleep 1.0  # let curses init + header render
      master.print "/q\r"
      Process.wait(pid)
      pid = nil
    end
    pass "echo_shell exited within 15s"
  ensure
    if pid
      begin
        Process.kill("KILL", pid)
        Process.wait(pid)
      rescue Errno::ESRCH, Errno::ECHILD
        # already gone
      end
    end
  end
end
