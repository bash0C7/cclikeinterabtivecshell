# frozen_string_literal: true

require "reline"
require_relative "hotkey_spec"

module Baslash
  # Walk the slash registry; for every entry that carries a hotkey, define
  # a uniquely named instance method on Reline::LineEditor and bind the
  # parsed byte sequence to that method symbol via
  # Reline.core.config.add_default_key_binding.
  #
  # Reline 0.6.3 dispatches a matched key sequence by symbol with
  # __send__(method_symbol) and refuses non-method targets in
  # wrap_method_call. Proc/lambda targets are not viable; per-hotkey
  # defined methods are required.
  module HotkeyInstaller
    METHOD_PREFIX = "__baslash_hotkey_"

    # Methods are defined on this module and included once into
    # Reline::LineEditor. Using a module (instead of defining straight
    # onto Reline::LineEditor) keeps UnboundMethod#bind permissive enough
    # for tests that exercise the body against a stand-in object, while
    # still letting Reline's __send__ dispatch find the methods on the
    # real line editor.
    Methods = Module.new
    @installed_into_reline = false

    def self.install(builder)
      ensure_included_in_line_editor
      seen_bytes = {}
      builder.slash_registry.each do |name, entry|
        spec = entry[:hotkey]
        next unless spec
        bytes = Baslash::HotkeySpec.parse(spec)
        if (prev = seen_bytes[bytes])
          builder.logger.warn(
            "hotkey conflict: #{Baslash::HotkeySpec.format(spec)} already bound to /#{prev}; /#{name} overrides"
          )
        end
        seen_bytes[bytes] = name

        define_hotkey_method(name)
        Reline.core.config.add_default_key_binding(bytes, method_name_for(name))
      end
    end

    def self.method_name_for(name)
      :"#{METHOD_PREFIX}#{name}"
    end

    def self.ensure_included_in_line_editor
      return if @installed_into_reline
      Reline::LineEditor.include(Methods)
      @installed_into_reline = true
    end

    def self.define_hotkey_method(name)
      method_name = method_name_for(name)
      command_line = "/#{name}"
      Methods.define_method(method_name) do |_key|
        bol = @buffer_of_lines
        next unless bol.is_a?(Array) && bol.size == 1
        idx = @line_index || 0
        next unless bol[idx].to_s.empty?
        set_current_line(command_line, command_line.bytesize)
        finish
      end
    end
  end
end
