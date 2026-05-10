require "socket"
require "json"

module Cclikesh
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
            begin
              ready = IO.select([@sock], nil, nil, 0.1)
              next unless ready
              client = begin
                @sock.accept_nonblock
              rescue IO::WaitReadable
                next
              end
              line = client.gets
              if line
                cmd = JSON.parse(line, symbolize_names: true)
                result = yield(cmd)
                client.puts(result.to_json)
              end
              client.close rescue nil
            rescue Errno::EBADF
              # Socket closed during select, exit gracefully
              break
            end
          end
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
