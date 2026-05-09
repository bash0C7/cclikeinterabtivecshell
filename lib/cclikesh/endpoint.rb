# frozen_string_literal: true

require "tmpdir"

module Cclikesh
  module Endpoint
    def self.uri(role)
      path = File.join(Dir.tmpdir, "cclikesh-#{Process.pid}-#{role}.sock")
      "drbunix://#{path}"
    end
  end
end
