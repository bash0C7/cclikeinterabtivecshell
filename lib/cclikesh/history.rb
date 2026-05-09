# frozen_string_literal: true

require "fileutils"
require "digest"

module Cclikesh
  module History
    HIST_DIR = File.expand_path("~/.cclikesh/history")

    def self.path_for(cwd)
      File.join(HIST_DIR, "#{Digest::SHA1.hexdigest(cwd.to_s)[0, 16]}.txt")
    end

    def self.load(path)
      return [] unless File.exist?(path)
      File.readlines(path, chomp: true).map { |l| decode(l) }
    rescue StandardError
      []
    end

    def self.save(path, entries)
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, entries.map { |e| encode(e) }.join("\n"))
    rescue StandardError
      # tolerate persistence failure
    end

    def self.encode(s)
      s.to_s.gsub("\\") { "\\\\" }.gsub("\n") { "\\n" }
    end

    def self.decode(s)
      result = +""
      i = 0
      while i < s.length
        c = s[i]
        if c == "\\" && i + 1 < s.length
          n = s[i + 1]
          case n
          when "n"  then result << "\n"; i += 2
          when "\\" then result << "\\"; i += 2
          else      result << c; i += 1
          end
        else
          result << c; i += 1
        end
      end
      result
    end
  end
end
