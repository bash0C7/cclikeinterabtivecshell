# frozen_string_literal: true

require_relative "test_helper"
require "pty"
require "timeout"

class TestE2EPTY < Test::Unit::TestCase
  ROOT = File.expand_path("..", __dir__)

  def test_echo_then_quit
    output = +""
    pid = nil
    Timeout.timeout(20) do
      master, slave = PTY.open
      pid = spawn(
        "bundle", "exec", "ruby", "-Ilib", File.join(ROOT, "examples/echo_shell.rb"),
        in: slave, out: slave, err: slave, chdir: ROOT
      )
      slave.close
      drain_for(master, output, 1.0)
      master.print "hello\r"
      drain_for(master, output, 1.0)
      master.print "/q\r"
      drain_for(master, output, 2.0)
      Process.wait(pid)
      pid = nil
    end
    assert_match(/you said: hello/, output)
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

  private

  def drain_for(io, buf, secs)
    deadline = Time.now + secs
    loop do
      remaining = deadline - Time.now
      break if remaining <= 0
      ready = IO.select([io], nil, nil, [remaining, 0.05].min)
      next unless ready
      begin
        buf << io.read_nonblock(4096)
      rescue IO::WaitReadable, EOFError
        next
      end
    end
  end
end
