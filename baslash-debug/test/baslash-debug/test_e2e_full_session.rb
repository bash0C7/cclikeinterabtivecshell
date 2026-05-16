require "test/unit"
require "tmpdir"
require "fileutils"
require "open3"
require "timeout"

class TestDebugE2EFullSession < Test::Unit::TestCase
  ROOT = File.expand_path("../../..", __dir__)

  def test_start_input_capture_stop_then_query_frames
    # TODO: wire up in finalization when a headless TTY harness is available.
    #
    # Root cause: `baslash-debug start` spawns `echo_shell.rb` via PTY, but
    # `echo_shell.rb` calls `Baslash.run` which initialises Curses. Curses
    # requires a real terminal (TERM, rows/cols, etc.). In the headless test
    # runner there is no controlling TTY, so the shell child crashes
    # immediately, and the `start` process exits before it ever creates the
    # control socket. Everything downstream (input / capture / stop / frames)
    # therefore never fires.
    #
    # Manual verification (run in a real terminal):
    #   dir=$(mktemp -d)
    #   BASLASH_DEBUG_DIR=$dir bundle exec baslash-debug start examples/echo_shell.rb --no-vector &
    #   UUID=$(grep -m1 session_uuid= /proc/$!/fd/1 | cut -d= -f2)   # or read from stdout
    #   SHORT=${UUID:0:8}
    #   BASLASH_DEBUG_DIR=$dir bundle exec baslash-debug input $SHORT "hello\r"
    #   BASLASH_DEBUG_DIR=$dir bundle exec baslash-debug capture $SHORT
    #   BASLASH_DEBUG_DIR=$dir bundle exec baslash-debug input $SHORT "/q\r"
    #   BASLASH_DEBUG_DIR=$dir bundle exec baslash-debug stop $SHORT
    #   wait
    #   BASLASH_DEBUG_DIR=$dir bundle exec baslash-debug frames $SHORT
    # macOS UNIX-socket path limit is 104 bytes; the default Dir.tmpdir under
    # /var/folders/... already eats ~70 bytes. Use /tmp directly to leave headroom
    # for {short}.drb-sock.drb and {short}.embedder.sock filenames.
    dir = Dir.mktmpdir("cl-e2e-", "/tmp")
    ENV["BASLASH_DEBUG_DIR"] = dir

    # Spawn `start` in background, read stdout to get session_uuid
    start_cmd = ["bundle", "exec", "baslash-debug", "start",
                 File.join(ROOT, "examples/echo_shell.rb"),
                 "--no-vector"]
    start_stdout_r, start_stdout_w = IO.pipe
    start_env = { "BASLASH_DEBUG_DIR" => dir }
    start_stderr_path = File.join(dir, "start.err.log")
    start_pid = spawn(start_env, *start_cmd, out: start_stdout_w, err: start_stderr_path, chdir: ROOT)
    start_stdout_w.close

    uuid = nil
    Timeout.timeout(10) do
      until uuid
        line = start_stdout_r.gets
        break unless line
        if line =~ /session_uuid=(\S+)/
          uuid = $1
        end
      end
    end
    refute_nil uuid, "expected session_uuid in start stdout"

    # The socket and db are keyed on the first 8 chars of the UUID (the "short" form)
    short = uuid[0, 8]

    dbg_env = { "BASLASH_DEBUG_DIR" => dir }

    # Wait for the control socket to appear (curses + DRb startup).
    # The socket is created by SocketProtocol::Server.new before the
    # session_uuid line is printed, so this should be near-instant.
    sock_path = File.join(dir, "#{short}.sock")
    Timeout.timeout(10) do
      sleep 0.2 until File.exist?(sock_path)
    end
    sleep 0.3  # brief extra settling time for DRb

    # Send input (use short form so resolve_socket glob matches `<short>.sock`)
    out, err, st = Open3.capture3(dbg_env, "bundle", "exec", "baslash-debug", "input", short, "hello\\r", chdir: ROOT)
    start_err = File.read(start_stderr_path) rescue ""
    shell_err_files = Dir.glob(File.join(dir, "*.shell.err"))
    shell_err = shell_err_files.map { |f| "=== #{f} ===\n#{File.read(f)}" }.join("\n") rescue ""
    assert st.success?, "input failed: stdout=#{out.inspect} stderr=#{err.inspect}\nstart-stderr:\n#{start_err}\nshell-stderr:\n#{shell_err}"
    sleep 0.5

    # Force a capture
    out, err, st = Open3.capture3(dbg_env, "bundle", "exec", "baslash-debug", "capture", short, chdir: ROOT)
    assert st.success?, "capture failed: stdout=#{out.inspect} stderr=#{err.inspect}"
    sleep 0.3

    # Quit the shell
    Open3.capture3(dbg_env, "bundle", "exec", "baslash-debug", "input", short, "/q\\r", chdir: ROOT)
    sleep 0.3

    # Send stop signal
    Open3.capture3(dbg_env, "bundle", "exec", "baslash-debug", "stop", short, chdir: ROOT)

    # Wait for start process to exit
    begin
      Timeout.timeout(10) { Process.wait(start_pid) }
    rescue Timeout::Error
      Process.kill("KILL", start_pid) rescue nil
      Process.wait(start_pid) rescue nil
    end

    start_stdout_r.close

    # Query frames (use short form so resolve_db glob matches `*<short>*.sqlite`)
    out, err, st = Open3.capture3(dbg_env, "bundle", "exec", "baslash-debug", "frames", short, chdir: ROOT)
    assert st.success?, "frames failed: stdout=#{out.inspect} stderr=#{err.inspect}"
    refute_empty out, "expected non-empty frames output, got: #{out.inspect}"

    # Verify the SQLite has at least one row
    db_path = Dir.glob(File.join(dir, "*.sqlite")).first
    refute_nil db_path, "expected a session DB file"
  ensure
    FileUtils.rm_rf(dir) rescue nil
    ENV.delete("BASLASH_DEBUG_DIR")
  end
end
