# frozen_string_literal: true

require "drb/drb"
require "drb/unix"
require_relative "endpoint"

module Cclikesh
  module Forking
    # Spawn an F (child) process via fork. Parent serves `registry` over a
    # UNIX-socket DRb endpoint; child receives that URI and runs the given
    # block. Returns the child's Process::Status when it exits.
    def self.run(registry)
      handlers_uri = Endpoint.uri(:handlers)
      DRb.start_service(handlers_uri, registry)

      child_pid = fork do
        DRb.stop_service # detach inherited service so child runs cleanly
        yield handlers_uri
      end

      Process.wait(child_pid)
      DRb.stop_service
      $?
    end
  end
end
