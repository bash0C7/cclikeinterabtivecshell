# frozen_string_literal: true

require "irb"
require "irb/completion"

class IrbCompleter
  def initialize(bind)
    @binding = bind
    @completor = build_completor
  end

  def candidates(buf, pos)
    pre = buf[0...pos] || ""
    return [] if pre.strip.empty?
    result = @completor.completion_candidates("", pre, "", bind: @binding)
    Array(result).uniq
  rescue StandardError
    []
  end

  private

  def build_completor
    require "irb/type_completion/completor"
    IRB::TypeCompletion::Completor.new
  rescue LoadError
    IRB::RegexpCompletor.new
  end
end
