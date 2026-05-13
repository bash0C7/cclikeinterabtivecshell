# frozen_string_literal: true

class CwdHolder
  def initialize
    @initial = Dir.pwd
    @cwd = @initial
  end

  def pwd
    @cwd
  end

  def cd(path)
    target =
      if path.nil? || path.empty? || path == "~"
        File.realpath(ENV["HOME"])
      else
        File.expand_path(path, @cwd)
      end
    raise Errno::ENOENT, target unless Dir.exist?(target)
    @cwd = target
    true
  end

  def reset
    @cwd = @initial
    true
  end
end
