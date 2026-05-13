# frozen_string_literal: true

class EnvHolder
  def initialize
    @initial = ENV.to_h.freeze
    @env = ENV.to_h
  end

  def snapshot
    @env.dup.freeze
  end

  def set(name, value)
    @env[name.to_s] = value.to_s
  end

  def unset(name)
    @env.delete(name.to_s)
  end

  def reset
    @env = @initial.dup
    true
  end

  def size
    @env.size
  end
end
