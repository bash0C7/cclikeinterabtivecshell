# frozen_string_literal: true

class IrbCompleter
  WORD_PATTERN = /[A-Za-z_][A-Za-z0-9_]*\z/.freeze

  def initialize(bind)
    @binding = bind
  end

  def candidates(buf, pos)
    prefix = buf[0...pos] || ""
    word = prefix[WORD_PATTERN]
    return [] if word.nil? || word.empty?

    pool = collect_pool
    pool.select { |c| c.start_with?(word) }.uniq
  end

  private

  def collect_pool
    locals = @binding.local_variables.map(&:to_s)
    constants = Object.constants.map(&:to_s)
    methods = Kernel.instance_methods.map(&:to_s) + Kernel.private_instance_methods.map(&:to_s)
    locals + constants + methods
  end
end
