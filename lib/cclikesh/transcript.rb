# frozen_string_literal: true

module Cclikesh
  module Transcript
    @lines = []
    @mutex = Mutex.new

    ANSI_RE = /\e\[[0-9;]*[a-zA-Z]/

    def self.record(line)
      return if line.nil?
      stripped = line.to_s.gsub(ANSI_RE, "")
      return if stripped.empty?
      @mutex.synchronize { @lines << stripped }
    end

    def self.lines
      @mutex.synchronize { @lines.dup }
    end

    def self.clear!
      @mutex.synchronize { @lines.clear }
    end

    def self.save(path)
      data = lines.join("\n")
      data << "\n" unless data.empty?
      File.write(path, data)
      path
    end
  end
end
