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

    assert_match(/\e\[32myou said: hello\e\[0m/, output,
                 "expected green-styled echoed line in PTY output. Got:\n#{output.inspect}")
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

  def test_slow_live_slot_then_quit
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

      master.print "/slow\r"
      sleep 1.0  # let live slot run all 3 ticks (~0.3s) + auto commit
      master.print "/quit\r"

      drain_until_eof_or_timeout_for(master, output, 5, /done/)
      Process.wait(pid)
      pid = nil
    end

    assert_match(/Roosting/, output,
                 "expected at least one live update. Got:\n#{output.inspect}")
    assert_match(/Roosting\.\.\. 3\/3/, output,
                 "expected final live update. Got:\n#{output.inspect}")
    assert_match(/\e\[2K/, output,
                 "expected ANSI line-clear from live slot. Got:\n#{output.inspect}")
    assert_match(/done/, output,
                 "expected committed 'done' append after live slot. Got:\n#{output.inspect}")
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

  def test_dialog_slash_renders_box
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

      master.print "/dialog hello-from-dialog\r"
      sleep 0.5
      master.print "/quit\r"

      drain_until_eof_or_timeout_for(master, output, 5, /hello-from-dialog/)
      Process.wait(pid)
      pid = nil
    end

    text = output.force_encoding("UTF-8")
    assert_match(/┌/, text, "expected dialog top border. Got:\n#{output.inspect}")
    assert_match(/hello-from-dialog/, text)
    assert_match(/└/, text, "expected dialog bottom border")
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

  def drain_until_eof_or_timeout_for(io, output, timeout, sentinel)
    deadline = Time.now + timeout
    while Time.now < deadline
      ready = IO.select([io], nil, nil, 0.3)
      unless ready
        break if output.match?(sentinel)
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
