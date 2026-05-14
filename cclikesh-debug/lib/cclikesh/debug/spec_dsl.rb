require "securerandom"
require_relative "pty_runner"
require_relative "pty_storage"
require_relative "captured"

module Cclikesh
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
        def spawn(argv:, cols:, rows:, env: {})
          raise DslError, "session: only one spawn per session" if @spawn_args
          @spawn_args = { argv: argv, cols: cols, rows: rows, env: env }
        end
        def wait(seconds);  @steps << [:wait, seconds.to_f]; end
        def send(str);      @steps << [:send, str.to_s];    end
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
        begin
          storage.insert_session(
            uuid: uuid, argv: scope.spawn_args[:argv],
            cols: scope.spawn_args[:cols], rows: scope.spawn_args[:rows],
            env:  scope.spawn_args[:env],
            spec_path: spec_path.to_s, timeout_sec: scope.timeout_sec
          )
          sink = ->(ts:, dir:, bytes:) {
            storage.insert_event(session_uuid: uuid, ts: ts, dir: dir, bytes: bytes)
          }
          runner = PtyRunner.new(
            argv: scope.spawn_args[:argv],
            cols: scope.spawn_args[:cols],
            rows: scope.spawn_args[:rows],
            env:  scope.spawn_args[:env],
            timeout_sec: scope.timeout_sec,
            event_sink: sink
          )
          status = runner.run do |api|
            scope.each_step do |kind, payload|
              case kind
              when :wait then api.wait(payload)
              when :send then api.send(payload)
              end
            end
          end
          storage.mark_ended(uuid: uuid, exit_status: status)
          captured = Captured.from_storage(storage, uuid)
          Result.new(session_uuid: uuid, exit_status: status,
                     captured: captured, expects: top.expects)
        ensure
          storage.close
        end
      end
    end
  end
end
