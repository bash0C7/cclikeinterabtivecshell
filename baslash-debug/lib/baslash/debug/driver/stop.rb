require_relative "../socket_protocol"
require_relative "input"

module Baslash
  module Debug
    module Driver
      module Stop
        def self.call(argv)
          session = argv.shift or abort("usage: baslash-debug stop <session>")
          sock = Baslash::Debug::Driver::Input.resolve_socket(session)
          Baslash::Debug::SocketProtocol::Client.new(sock).send_command(op: "stop")
        end
      end
    end
  end
end
