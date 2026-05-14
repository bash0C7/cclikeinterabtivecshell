# frozen_string_literal: true

module Cclikesh
  # Slash commands registered into every cclikesh app's slash registry
  # by Runner.run without any opt-in. Currently /exit /q /help. Later
  # plugin command sets (debug, transcript, …) are layered on top with
  # their own `Cclikesh::XxxCommands.register(registry, ...)`.
  #
  # /help iterates the slash registry at call time so it lists whatever
  # else has been registered (default + plugin + example-specific).
  # The registry reference lives in a module-level slot rather than as
  # a closed-over local, so the /help body survives Ractor.shareable_proc
  # wrapping inside SlashRegistry#register.
  module DefaultCommands
    @registry = nil

    def self.current_registry
      @registry
    end

    def self.register(registry)
      @registry = registry
      registry.register(:exit, EXIT_BODY, description: "exit")
      registry.register(:q,    EXIT_BODY, description: "exit")
      registry.register(:help, HELP_BODY, description: "list slash commands")
    end

    EXIT_BODY = ->(_args, ctx) { ctx.quit }

    HELP_BODY = ->(_args, ctx) {
      Cclikesh::DefaultCommands.current_registry.each do |name, entry|
        desc = entry[:description].to_s
        line = desc.empty? ? "/#{name}" : "/#{name}  - #{desc}"
        ctx.display.append(line, style: :dim)
      end
    }
  end
end
