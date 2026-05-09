# frozen_string_literal: true

require_relative "test_helper"
require "pty"
require "timeout"

class TestE2EPTY < Test::Unit::TestCase
  PROJECT_ROOT = File.expand_path("..", __dir__)
  ECHO_SHELL = File.join(PROJECT_ROOT, "examples", "echo_shell.rb")

  def test_echo_then_quit_produces_expected_output
    output = String.new
    pid = nil

    Timeout.timeout(20) do
      master, slave = PTY.open
      pid = spawn(
        "bundle", "exec", "ruby", "-Ilib", ECHO_SHELL,
        in: slave, out: slave, err: slave,
        chdir: PROJECT_ROOT
      )
      slave.close

      wait_for_prompt(master, output, 8)

      master.print "hello\r"
      sleep 0.5
      master.print "/quit\r"

      drain_until_eof_or_timeout(master, output, 5)
      Process.wait(pid)
      pid = nil
    end

    assert_match(/you said: hello/, output,
                 "expected echoed line in PTY output. Got:\n#{output.inspect}")
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

  def wait_for_prompt(io, output, timeout)
    deadline = Time.now + timeout
    until output.include?("> ")
      raise "timeout waiting for prompt; got #{output.inspect}" if Time.now > deadline
      ready = IO.select([io], nil, nil, 0.2)
      next unless ready
      begin
        chunk = io.read_nonblock(4096)
      rescue IO::WaitReadable
        next
      rescue EOFError, Errno::EIO
        return
      end
      output << chunk
    end
  end

  def drain_until_eof_or_timeout(io, output, timeout)
    deadline = Time.now + timeout
    while Time.now < deadline
      ready = IO.select([io], nil, nil, 0.3)
      unless ready
        break if output.include?("you said:")
        next
      end
      begin
        chunk = io.read_nonblock(4096)
      rescue IO::WaitReadable
        next
      rescue EOFError, Errno::EIO
        return
      end
      output << chunk
    end
  end
end
