require "pty"
require "io/console"

module Baslash
  module Debug
    class PtyRunner
      SELECT_TICK = 0.05
      KILL_GRACE  = 0.5

      class ScriptApi
        def initialize(runner)
          @runner = runner
        end
        def send(str);    @runner.script_send(str);          end
        def wait(seconds);@runner.script_wait(seconds.to_f); end
        def resize(cols, rows); @runner.script_resize(cols, rows); end
      end

      def initialize(argv:, cols:, rows:, env:, timeout_sec:, event_sink:, clear_size_env: false)
        @argv            = argv
        @cols            = cols
        @rows            = rows
        @env             = env
        @timeout_sec     = timeout_sec.to_f
        @event_sink      = event_sink
        @clear_size_env  = clear_size_env
      end

      def run
        @started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        @r, @w, @pid = PTY.spawn(env_for_spawn, *@argv)
        @r.winsize = [@rows, @cols] rescue nil  # Errno::ENOTTY on non-terminal fd (tests)
        @child_alive = true
        @timed_out   = false
        @script_pending_wait_until = nil
        @script_fiber = Fiber.new { yield(ScriptApi.new(self)) if block_given? }
        loop_until_child_exits
        reap_exit_status
      ensure
        cleanup_child
      end

      def script_send(str)
        bytes = str.b
        emit(now_ts, "i", bytes)
        @w.write(bytes)
        @w.flush
      end

      def script_wait(seconds)
        @script_pending_wait_until = now_ts + seconds
        Fiber.yield
      end

      def script_resize(cols, rows)
        # IO#winsize= takes [rows, cols] per io/console. Public arg order
        # mirrors PtyRunner.new(cols:, rows:) for consistency.
        @r.winsize = [rows, cols]
      rescue Errno::ENOTTY, IOError
        # Non-PTY masters (test stubs) cannot accept winsize; ignore.
        nil
      end

      private

      def env_for_spawn
        merged = ENV.to_h.merge(@env || {})
        if @clear_size_env
          merged.delete("COLUMNS")
          merged.delete("LINES")
        else
          merged["COLUMNS"] = @cols.to_s
          merged["LINES"]   = @rows.to_s
        end
        merged
      end

      def loop_until_child_exits
        resume_script_if_ready
        while @child_alive
          drain_pty(SELECT_TICK)
          resume_script_if_ready
          reap_no_hang
          break unless @child_alive
          if now_ts > @timeout_sec
            send_signals_and_break
            break
          end
        end
        final_deadline = now_ts + 0.5
        while now_ts < final_deadline && pty_has_more_to_read?(0.05)
          drain_pty(0.05)
        end
      end

      def drain_pty(timeout)
        return unless @r && !@r.closed?
        ready, = IO.select([@r], nil, nil, timeout)
        return unless ready
        loop do
          chunk = @r.read_nonblock(4096)
          emit(now_ts, "o", chunk) unless chunk.empty?
        end
      rescue IO::WaitReadable
        nil
      rescue EOFError, Errno::EIO
        @child_alive = false
      end

      def pty_has_more_to_read?(timeout)
        return false unless @r && !@r.closed?
        ready, = IO.select([@r], nil, nil, timeout)
        !ready.nil? && !ready.empty?
      rescue IOError
        false
      end

      def resume_script_if_ready
        return unless @script_fiber.alive?
        return if @script_pending_wait_until && now_ts < @script_pending_wait_until
        @script_pending_wait_until = nil
        # Script exceptions propagate intentionally — a broken spec is the caller's fault
        # and surfaces up through #run, with cleanup_child still running in the ensure.
        @script_fiber.resume
      end

      def send_signals_and_break
        return unless @pid
        Process.kill("TERM", @pid) rescue nil
        deadline = now_ts + KILL_GRACE
        until reap_no_hang || now_ts >= deadline
          drain_pty(SELECT_TICK)
        end
        Process.kill("KILL", @pid) rescue nil unless reap_no_hang
        @child_alive = false
        @timed_out   = true
      end

      def reap_no_hang
        return true unless @pid
        return true if @reaped_status
        pid, status = Process.waitpid2(@pid, Process::WNOHANG)
        return false unless pid
        @reaped_status = status
        @child_alive   = false
        true
      rescue Errno::ECHILD
        @child_alive = false
        true
      end

      def reap_exit_status
        return nil if @timed_out
        status = @reaped_status
        if status.nil? && @pid
          _pid, status = Process.waitpid2(@pid) rescue [nil, nil]
        end
        return nil unless status
        emit(now_ts, "x", status.exitstatus.to_s)
        status.exitstatus
      end

      def cleanup_child
        @r.close rescue nil
        @w.close rescue nil
        if @pid
          Process.kill("KILL", @pid) rescue nil if @child_alive
          Process.waitpid(@pid, Process::WNOHANG) rescue nil
        end
      end

      def emit(ts, dir, bytes)
        @event_sink.call(ts: ts, dir: dir, bytes: bytes.dup.force_encoding(Encoding::ASCII_8BIT))
      end

      def now_ts
        Process.clock_gettime(Process::CLOCK_MONOTONIC) - @started_at
      end
    end
  end
end
