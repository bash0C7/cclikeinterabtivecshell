require "pty"
require "securerandom"
require "fileutils"
require "tmpdir"
require "io/console"
require "drb/drb"
require "timeout"
require_relative "../recorder"
require_relative "../storage"
require_relative "../socket_protocol"
require_relative "../embedder_pool"

module Baslash
  module Debug
    module Driver
      module Start
        def self.call(argv)
          target = argv.shift or abort("usage: baslash-debug start <example.rb> [opts]")

          cadence_ms = parse_int(argv, "--cadence-ms", 50)
          no_vector  = argv.delete("--no-vector") ? true : false
          embed_after_stop = argv.delete("--embed-after-stop") ? true : false
          note       = parse_str(argv, "--note", nil)
          out_dir    = ENV["BASLASH_DEBUG_DIR"] || File.join(Dir.pwd, "tmp", "baslash-debug")
          FileUtils.mkdir_p(out_dir)

          uuid    = SecureRandom.uuid
          short   = uuid[0, 8]
          ts_str  = Time.now.strftime("%Y-%m-%d-%H%M%S")
          pid     = Process.pid
          db_path = File.join(out_dir, "#{ts_str}-#{pid}-#{short}.sqlite")
          sock    = File.join(out_dir, "#{short}.sock")
          drb_sock_base = File.join(out_dir, "#{short}.drb-sock")
          embedder_sock = File.join(out_dir, "#{short}.embedder.sock")

          rows, cols = (IO.console.winsize rescue [24, 80])

          storage = Storage.create(db_path,
            session_uuid: uuid, shell_argv: ["ruby", target], baslash_ver: "0.2.0",
            rows: rows, cols: cols, embedder: EmbedderPool::MODEL_NAME, notes: note)

          # Allocate PTY for the shell child. Set TERM and winsize so Curses can
          # initialise correctly even from headless test runners (priority-2 fix).
          master, slave = PTY.open
          slave.winsize = [rows, cols]
          # Use `bundle exec ruby` so the child sees the same Bundler environment
          # as the parent (development mode); when the gem is installed normally,
          # rubygems' load path will be sufficient and bundler is a harmless wrapper.
          # stderr also tees to a log file so a failing child can be diagnosed
          # post-mortem (the slave PTY otherwise eats it through the recorder).
          shell_err_log = File.join(out_dir, "#{short}.shell.err")
          child_pid = spawn(
            {
              "BASLASH_DEBUG_SOCK" => drb_sock_base,
              "TERM"                => ENV["TERM"] || "xterm-256color",
              "LINES"               => rows.to_s,
              "COLUMNS"             => cols.to_s
            },
            "bash", "-c",
            "exec bundle exec ruby \"$0\" 2> >(tee -a \"$1\" >&2)",
            target, shell_err_log,
            in: slave, out: slave, err: slave
          )
          slave.close

          drb_uri = "drbunix:#{drb_sock_base}.drb"
          sleep 0.5  # let shell start its DRb service

          recorder = Recorder.new(
            storage: storage,
            embedder_factory: -> { EmbedderPool.new },  # legacy synthetic path only
            no_vector: no_vector || embed_after_stop  # both skip live embedding
          )
          recorder.start_pipeline!(pty_master_fd: master.fileno)

          # Connect to shell's DRb so main can pull snapshots (FrameBuilder Ractor can't)
          DRb.start_service
          shell_adapter = DRbObject.new_with_uri(drb_uri)

          server = SocketProtocol::Server.new(sock)

          puts "session_uuid=#{uuid}"
          puts "session_db=#{db_path}"
          puts "control_socket=#{sock}"
          $stdout.flush

          # Main loop: accept socket commands and run periodic capture in the
          # same Ractor. No Thread.new; periodic cadence is measured between
          # accept_one() returns. Stop pivots on the "stop" command.
          stopped = false
          last_periodic = Time.now
          period_secs = cadence_ms / 1000.0

          until stopped
            server.accept_one(timeout: [period_secs, 0.05].max) do |cmd|
              case cmd[:op]
              when "input"
                master.write(decode_keys(cmd[:text].to_s))
                { ok: true }
              when "capture"
                snap = (shell_adapter.debug_snapshot rescue nil)
                if snap
                  recorder.trigger_capture!(
                    trigger: "on_demand", event_kind: nil, snapshot: snap
                  )
                end
                { ok: true }
              when "stop"
                Process.kill("TERM", child_pid) rescue nil
                recorder.stop!
                if embed_after_stop
                  embed_pending_via_subprocess(
                    recorder: recorder,
                    sock_path: embedder_sock,
                    log_path:  File.join(out_dir, "#{short}.embedder.log")
                  )
                end
                storage.mark_ended!
                storage.close
                server.shutdown
                stopped = true
                { ok: true, stopped: true }
              else
                { ok: false, error: "unknown op: #{cmd[:op]}" }
              end
            end

            # Periodic capture. We measure from last_periodic so a string of
            # quick socket commands cannot delay the next periodic forever.
            # snap=nil is normal during shell warm-up (DRb not yet ready);
            # we only stop on explicit "stop" command or child shell exit.
            if !stopped && (Time.now - last_periodic) >= period_secs
              snap = (shell_adapter.debug_snapshot rescue nil)
              if snap
                recorder.trigger_capture!(trigger: "periodic", event_kind: nil, snapshot: snap)
              end
              last_periodic = Time.now
            end

            # Detect child shell exit so we don't loop forever after the user
            # quits the shell (e.g. /q in echo_shell). non-blocking wait.
            if !stopped && Process.waitpid(child_pid, Process::WNOHANG)
              stopped = true
              recorder.stop!
              storage.mark_ended!
              storage.close
              server.shutdown
            end
          end

          Process.wait(child_pid) rescue nil
        end

        def self.embed_pending_via_subprocess(recorder:, sock_path:, log_path:)
          embedder_pid = spawn(
            "baslash-debug-embedder", sock_path,
            out: log_path, err: [:child, :out]
          )
          Timeout.timeout(120) { sleep 0.2 until File.exist?(sock_path) }
          sleep 0.5
          proxy = DRbObject.new_with_uri("drbunix:#{sock_path}")
          recorder.embed_pending!(proxy: proxy)
        ensure
          Process.kill("TERM", embedder_pid) if embedder_pid rescue nil
          Process.wait(embedder_pid) if embedder_pid rescue nil
          File.unlink(sock_path) if File.exist?(sock_path)
        end

        def self.parse_int(argv, flag, default)
          idx = argv.index(flag)
          return default unless idx
          argv.delete_at(idx)
          Integer(argv.delete_at(idx))
        end

        def self.parse_str(argv, flag, default)
          idx = argv.index(flag)
          return default unless idx
          argv.delete_at(idx)
          argv.delete_at(idx)
        end

        def self.decode_keys(s)
          s.gsub('\\r', "\r").gsub('\\t', "\t").gsub('\\n', "\n").gsub('\\e', "\e")
        end
      end
    end
  end
end
