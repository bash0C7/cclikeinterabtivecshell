# frozen_string_literal: true

require_relative "baslash/version"
require_relative "baslash/style"
require_relative "baslash/title_bar"
require_relative "baslash/transcript"
require_relative "baslash/context"
require_relative "baslash/main_ctx"
require_relative "baslash/display"
require_relative "baslash/shareable_ref"
require_relative "baslash/slash_registry"
require_relative "baslash/ctx_proxy"
require_relative "baslash/sync_ctx"
# HandlerRactor is preserved for future explicit-background execution
# (Ctrl-B style), but excluded from the default load path. The default
# dispatch is synchronous via SyncCtx.
# require_relative "baslash/handler_ractor"
require_relative "baslash/slash_dispatcher"
require_relative "baslash/default_commands"
require_relative "baslash/reline_dialogs"
require_relative "baslash/builder"
require_relative "baslash/runner"

module Baslash
  def self.run(&block)
    builder = Builder.new
    block.call(builder)
    Runner.run(builder)
  end
end
