require_relative "../socket_protocol"
require_relative "input"

module Cclikesh
  module Debug
    module Driver
      module Stop
        def self.call(argv)
          session = argv.shift or abort("usage: cclikesh-debug stop <session>")
          sock = Cclikesh::Debug::Driver::Input.resolve_socket(session)
          Cclikesh::Debug::SocketProtocol::Client.new(sock).send_command(op: "stop")
        end
      end
    end
  end
end
