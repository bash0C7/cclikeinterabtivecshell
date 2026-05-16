require_relative "../socket_protocol"

module Baslash
  module Debug
    module Driver
      module Input
        def self.call(argv)
          session = argv.shift or abort("usage: baslash-debug input <session> <text>")
          text = argv.shift or abort("usage: baslash-debug input <session> <text>")
          sock = resolve_socket(session)
          res = Baslash::Debug::SocketProtocol::Client.new(sock).send_command(op: "input", text: text)
          abort("input failed: #{res}") unless res[:ok]
        end

        def self.resolve_socket(session)
          out_dir = ENV["BASLASH_DEBUG_DIR"] || File.join(Dir.pwd, "tmp", "baslash-debug")
          matches = Dir.glob(File.join(out_dir, "#{session}*.sock"))
          abort("no session socket matching #{session}") if matches.empty?
          matches.first
        end
      end
    end
  end
end
