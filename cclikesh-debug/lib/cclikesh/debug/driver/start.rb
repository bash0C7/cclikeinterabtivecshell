require "pty"
require "securerandom"
require "fileutils"
require "tmpdir"
require "io/console"
require "drb/drb"
require_relative "../recorder"
require_relative "../storage"
require_relative "../socket_protocol"
require_relative "../embedder_pool"

module Cclikesh
  module Debug
    module Driver
      module Start
        def self.call(argv)
          target = argv.shift or abort("usage: cclikesh-debug start <example.rb> [opts]")

          cadence_ms = parse_int(argv, "--cadence-ms", 50)
          no_vector  = argv.delete("--no-vector") ? true : false
          embed_after_stop = argv.delete("--embed-after-stop") ? true : false
          note       = parse_str(argv, "--note", nil)
          out_dir    = ENV["CCLIKESH_DEBUG_DIR"] || File.join(Dir.pwd, "tmp", "cclikesh-debug")
          FileUtils.mkdir_p(out_dir)

          uuid    = SecureRandom.uuid
          short   = uuid[0, 8]
          ts_str  = Time.now.strftime("%Y-%m-%d-%H%M%S")
          pid     = Process.pid
          db_path = File.join(out_dir, "#{ts_str}-#{pid}-#{short}.sqlite")
          sock    = File.join(out_dir, "#{short}.sock")
          drb_sock_base = File.join(out_dir, "#{short}.drb-sock")

          rows, cols = (IO.console.winsize rescue [24, 80])

          storage = Storage.create(db_path,
            session_uuid: uuid, shell_argv: ["ruby", target], cclikesh_ver: "0.2.0",
            rows: rows, cols: cols, embedder: EmbedderPool::MODEL_NAME, notes: note)

          master, slave = PTY.open
          child_pid = spawn(
            { "CCLIKESH_DEBUG_SOCK" => drb_sock_base },
            "ruby", target,
            in: slave, out: slave, err: slave
          )
          slave.close

          drb_uri = "drbunix:#{drb_sock_base}.drb"
          sleep 0.5  # let shell start its DRb service

          recorder = Recorder.new(
            storage: storage,
            embedder_factory: -> { EmbedderPool.new },
            no_vector: no_vector || embed_after_stop  # both skip live embedding
          )
          recorder.start_pipeline!(pty_master_fd: master.fileno)

          # Connect to shell's DRb so main can pull snapshots (FrameBuilder Ractor can't)
          DRb.start_service
          shell_adapter = DRbObject.new_with_uri(drb_uri)

          server = SocketProtocol::Server.new(sock)

          server_thread = Thread.new do
            server.serve do |cmd|
              case cmd[:op]
              when "input"
                master.write(decode_keys(cmd[:text].to_s))
                { ok: true }
              when "capture"
                # Main pulls snapshot via DRb, then triggers Recorder
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
                  recorder.embed_pending!
                end
                storage.mark_ended!
                storage.close
                server.shutdown
                { ok: true, stopped: true }
              else
                { ok: false, error: "unknown op: #{cmd[:op]}" }
              end
            end
          end

          # Periodic capture loop in a background thread
          periodic_thread = Thread.new do
            loop do
              sleep cadence_ms / 1000.0
              snap = (shell_adapter.debug_snapshot rescue nil)
              break unless snap
              recorder.trigger_capture!(trigger: "periodic", event_kind: nil, snapshot: snap)
            end
          end

          puts "session_uuid=#{uuid}"
          puts "session_db=#{db_path}"
          puts "control_socket=#{sock}"
          $stdout.flush

          # Wait for child to exit (or stop command via socket)
          Process.wait(child_pid) rescue nil
          server.shutdown rescue nil
          server_thread.join(2.0) rescue nil
          periodic_thread.kill rescue nil
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
