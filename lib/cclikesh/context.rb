# frozen_string_literal: true

require "tmpdir"
require_relative "transcript"

module Cclikesh
  module Context
    @mutex = Mutex.new
    @state = {}
    @logger = nil
    @quit = false

    def self.init(logger:)
      @mutex.synchronize do
        @logger = logger
        @state = {}
        @quit = false
      end
    end

    def self.reset!
      @mutex.synchronize do
        @state = {}
        @logger = nil
        @quit = false
      end
    end

    def self.state
      @mutex.synchronize { @state.dup }
    end

    def self.state_set(key, value)
      @mutex.synchronize { @state[key.to_sym] = value }
    end

    def self.state_clear(key)
      @mutex.synchronize { @state.delete(key.to_sym) }
    end

    def self.logger
      @logger or raise "Cclikesh::Context not initialized"
    end

    def self.quit
      @mutex.synchronize { @quit = true }
    end

    def self.quit?
      @mutex.synchronize { @quit }
    end

    def self.transcript_lines
      Transcript.lines
    end

    def self.transcript_save(path = nil)
      target = path || File.join(Dir.tmpdir, "cclikesh-transcript-#{Process.pid}.log")
      Transcript.save(target)
    end
  end
end
