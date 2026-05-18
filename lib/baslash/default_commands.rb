# frozen_string_literal: true

module Baslash
  # Slash commands registered into every baslash app's slash registry
  # by Runner.run without any opt-in. Currently /exit /q /help. Later
  # plugin command sets (debug, transcript, …) are layered on top with
  # their own `Baslash::XxxCommands.register(registry, ...)`.
  #
  # /help must be registered AFTER all other commands via register_help(registry)
  # so its frozen snapshot of the registry sees every registered command.
  # Its body closes over an immutable array — no class instance variable
  # is read inside the handler Ractor, avoiding Ractor::IsolationError.
  module DefaultCommands
    EXIT_BODY = Ractor.make_shareable(->(_args, ctx) { ctx.quit })

    def self.register(registry)
      registry.register(:exit, EXIT_BODY, description: "exit")
      registry.register(:q,    EXIT_BODY, description: "exit")
    end

    # Call this AFTER all other commands have been registered. Builds a
    # /help body that closes over a frozen snapshot of the registry
    # entries at the moment of the call. Subsequent registrations will
    # not appear in /help (the snapshot is taken once).
    def self.register_help(registry)
      # Build snapshot of all commands registered so far, plus /help itself.
      # The snapshot is taken before registry.register(:help) so we add the
      # /help entry manually to keep it in the listing.
      existing = registry.all.map { |name, entry|
        [name.to_s, entry[:description].to_s, entry[:hotkey].to_s].freeze
      }
      existing << ["help", "list slash commands", ""].freeze
      snapshot = Ractor.make_shareable(existing.freeze)
      help_body = Ractor.make_shareable(->(_, ctx) {
        snapshot.each do |name, desc, hotkey|
          suffix =
            if hotkey.empty?
              ""
            else
              " (#{hotkey})"
            end
          line =
            if desc.empty?
              "/#{name}#{suffix}"
            else
              "/#{name}  - #{desc}#{suffix}"
            end
          ctx.display.append(line, style: :dim)
        end
      })
      registry.register(:help, help_body, description: "list slash commands")
    end
  end
end
