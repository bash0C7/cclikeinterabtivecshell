# frozen_string_literal: true

class IrbEvaluator
  attr_reader :binding

  def initialize
    @binding = fresh_binding
  end

  def evaluate(line)
    @binding.eval(line)
  end

  def reset
    @binding = fresh_binding
  end

  private

  def fresh_binding
    Object.new.instance_eval { binding }
  end
end
