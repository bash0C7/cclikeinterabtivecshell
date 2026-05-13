require_relative "cclikesh/version"
require_relative "cclikesh/style"
require_relative "cclikesh/transcript"
require_relative "cclikesh/context"
require_relative "cclikesh/main_ctx"
require_relative "cclikesh/chrome"
require_relative "cclikesh/display"
require_relative "cclikesh/shareable_ref"
require_relative "cclikesh/slash_registry"
require_relative "cclikesh/ctx_proxy"
require_relative "cclikesh/handler_ractor"
require_relative "cclikesh/slash_dispatcher"
require_relative "cclikesh/reline_dialogs"
require_relative "cclikesh/builder"
begin
  require_relative "cclikesh/debug_endpoint"
rescue LoadError
  # debug_endpoint is opt-in; will be added in a later task
end
require_relative "cclikesh/runner"

module Cclikesh
  def self.run(&block)
    builder = Builder.new
    block.call(builder)
    Runner.run(builder)
  end
end
