require "socket"
require "json"

module Baslash
  module Debug
    module SocketProtocol
      class Server
        def initialize(path)
          File.unlink(path) if File.exist?(path)
          @path = path
          @sock = UNIXServer.new(path)
          @stop = false
        end

        def serve
          until @stop
            accept_one(timeout: 0.1) { |cmd| yield(cmd) }
          end
        end

        # Single-shot accept that returns true if a command was handled,
        # false if the timeout expired with no client. Used by main-loop
        # callers that need to interleave other work (e.g. periodic capture)
        # without spawning a Thread.
        def accept_one(timeout:)
          return false if @stop
          ready = IO.select([@sock], nil, nil, timeout)
          return false unless ready
          client = begin
            @sock.accept_nonblock
          rescue IO::WaitReadable
            return false
          end
          line = client.gets
          if line
            cmd = JSON.parse(line, symbolize_names: true)
            result = yield(cmd)
            client.puts(result.to_json)
          end
          client.close rescue nil
          true
        rescue Errno::EBADF
          @stop = true
          false
        end

        def shutdown
          @stop = true
          @sock.close rescue nil
          File.unlink(@path) if File.exist?(@path)
        end
      end

      class Client
        def initialize(path)
          @path = path
        end

        def send_command(cmd)
          sock = UNIXSocket.new(@path)
          sock.puts(cmd.to_json)
          line = sock.gets
          line ? JSON.parse(line, symbolize_names: true) : {}
        ensure
          sock&.close
        end
      end
    end
  end
end
