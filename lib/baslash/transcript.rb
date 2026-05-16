# frozen_string_literal: true

module Baslash
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

    # Task 4 Display stub contract: reset state between tests.
    # Alias for clear! that callers may probe via respond_to?.
    def self.reset_for_test
      @mutex.synchronize { @lines.clear }
    end
  end
end
