module Baslash
  module Debug
    module Ractors
      module PtyReader
        def self.spawn(downstream:, master_fd:)
          Ractor.new(downstream, master_fd) do |down, fd|
            io = IO.for_fd(fd, "rb", autoclose: false)
            loop do
              begin
                chunk = io.read_nonblock(64 * 1024)
                ts = Process.clock_gettime(Process::CLOCK_MONOTONIC)
                down.send([:bytes, chunk.freeze, ts])
              rescue IO::WaitReadable
                IO.select([io], nil, nil, 0.05)
              rescue EOFError
                down.send([:eof])
                break
              rescue Errno::EIO
                down.send([:eof])
                break
              end
            end
          end
        end
      end
    end
  end
end
