require "securerandom"
require "tmpdir"
require "fileutils"
require_relative "pty_runner"
require_relative "pty_storage"
require_relative "captured"

module Baslash
  module Debug
    module SpecDSL
      DEFAULT_TIMEOUT = 30.0

      class DslError < StandardError; end

      Result = Struct.new(:session_uuid, :exit_status, :captured, :expects, keyword_init: true)

      class SessionScope
        attr_reader :timeout_sec, :spawn_args
        def initialize
          @timeout_sec = DEFAULT_TIMEOUT
          @spawn_args  = nil
          @steps       = []
        end
        def timeout(seconds)
          raise DslError, "timeout must come before spawn" if @spawn_args
          @timeout_sec = seconds.to_f
        end
        def spawn(argv:, cols:, rows:, env: {}, clear_size_env: false)
          raise DslError, "session: only one spawn per session" if @spawn_args
          @spawn_args = { argv: argv, cols: cols, rows: rows, env: env, clear_size_env: clear_size_env }
        end
        def wait(seconds);  @steps << [:wait, seconds.to_f]; end
        # Intentionally shadows Kernel#send inside the DSL block. The DSL
        # surface is locked by spec — do not rename. Internal code must never
        # call scope.send(symbol, ...) with the dispatcher meaning; use the
        # explicit accessors (each_step, spawn_args, timeout_sec) instead.
        def send(str);      @steps << [:send, str.to_s];    end
        def resize(cols, rows); @steps << [:resize, cols.to_i, rows.to_i]; end
        def each_step(&blk); @steps.each(&blk); end
      end

      class TopLevel
        def initialize
          @session_scope = nil
          @expects       = []
        end
        attr_reader :session_scope, :expects

        def session(_label, &blk)
          raise DslError, "only one session per spec" if @session_scope
          scope = SessionScope.new
          scope.instance_eval(&blk)
          raise DslError, "session must call spawn" unless scope.spawn_args
          @session_scope = scope
        end

        def expect(label, &blk)
          @expects << [label.to_s, blk]
        end
      end

      def self.evaluate(src, db_path:, spec_path:)
        top = TopLevel.new
        top.instance_eval(src, spec_path.to_s)
        raise DslError, "spec defined no session" unless top.session_scope
        run(top, db_path: db_path, spec_path: spec_path)
      end

      def self.run(top, db_path:, spec_path:)
        scope = top.session_scope
        storage = PtyStorage.open(db_path)
        uuid = SecureRandom.uuid
        diag_path = File.join(Dir.tmpdir, "baslash-diag-#{uuid}.log")
        spawn_env = (scope.spawn_args[:env] || {}).merge("BASLASH_LAYOUT_DIAG" => diag_path)
        begin
          storage.insert_session(
            uuid: uuid, argv: scope.spawn_args[:argv],
            cols: scope.spawn_args[:cols], rows: scope.spawn_args[:rows],
            env:  spawn_env,
            spec_path: spec_path.to_s, timeout_sec: scope.timeout_sec
          )
          sink = ->(ts:, dir:, bytes:) {
            storage.insert_event(session_uuid: uuid, ts: ts, dir: dir, bytes: bytes)
          }
          runner = PtyRunner.new(
            argv: scope.spawn_args[:argv],
            cols: scope.spawn_args[:cols],
            rows: scope.spawn_args[:rows],
            env:  spawn_env,
            timeout_sec: scope.timeout_sec,
            event_sink: sink,
            clear_size_env: scope.spawn_args[:clear_size_env] || false,
          )
          status = runner.run do |api|
            scope.each_step do |kind, *payload|
              case kind
              when :wait   then api.wait(payload.first)
              when :send   then api.send(payload.first)
              when :resize then api.resize(payload[0], payload[1])
              end
            end
          end
          storage.mark_ended(uuid: uuid, exit_status: status)
          diag_entries = parse_diag_log(diag_path)
          captured = Captured.from_storage(storage, uuid, diag_entries: diag_entries)
          Result.new(session_uuid: uuid, exit_status: status,
                     captured: captured, expects: top.expects)
        ensure
          storage.close
          FileUtils.rm_f(diag_path)
        end
      end

      def self.parse_diag_log(path)
        return [] unless File.exist?(path)
        File.readlines(path).map { |line| parse_diag_line(line) }.compact
      end

      def self.parse_diag_line(line)
        # Format: [ISO8601] <tag> curses.lines=<v> curses.cols=<v> maxyx=<v> winsize=<v> env_lines=<v> env_cols=<v>
        # chomp strips the trailing \n that File.readlines includes; \z anchors to end-of-string.
        m = line.chomp.match(/\A\[(?<ts>[^\]]+)\] (?<tag>\S+) curses\.lines=(?<lines>\S+) curses\.cols=(?<cols>\S+) maxyx=(?<maxyx>.*?) winsize=(?<winsize>.*?) env_lines=(?<env_lines>\S+) env_cols=(?<env_cols>\S+)\z/)
        return nil unless m
        {
          ts:        m[:ts],
          tag:       m[:tag],
          lines:     parse_diag_value(m[:lines]),
          cols:      parse_diag_value(m[:cols]),
          maxyx:     parse_diag_value(m[:maxyx]),
          winsize:   parse_diag_value(m[:winsize]),
          env_lines: parse_diag_value(m[:env_lines]),
          env_cols:  parse_diag_value(m[:env_cols]),
        }
      end

      # Parses Ruby `.inspect` output for the values produced by LayoutDiag:
      # nil, an Integer, an Array of Integers (or nil entries), or a "..." quoted string.
      def self.parse_diag_value(s)
        s = s.strip.chomp("\n")
        return nil if s == "nil"
        return Integer(s) if s.match?(/\A-?\d+\z/)
        if s.start_with?("[") && s.end_with?("]")
          inner = s[1..-2]
          return [] if inner.strip.empty?
          return inner.split(",").map { |x| parse_diag_value(x) }
        end
        if s.start_with?('"') && s.end_with?('"')
          return s[1..-2]
        end
        s
      end

      def self.dispatch_expects(result)
        result.expects.map do |label, blk|
          pass  = false
          err   = nil
          begin
            pass = !!blk.call(result.captured)
          rescue StandardError => e
            err  = e
            pass = false
          end
          { label: label, pass: pass, error: err }
        end
      end
    end
  end
end
