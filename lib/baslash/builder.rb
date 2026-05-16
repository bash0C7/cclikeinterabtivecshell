# frozen_string_literal: true

require "logger"
require_relative "slash_registry"
require_relative "shareable_ref"
require_relative "style"

module Baslash
  class Builder
    attr_reader :slash_registry, :state_refs,
                :on_submit_handler, :on_tab_handler,
                :on_start_handlers, :on_quit_handlers,
                :info_blocks, :status_row_blocks,
                :spinner_label_block, :prompt_suggestion_block,
                :shortcuts_hint_text, :header_config,
                :logger

    def initialize
      @slash_registry          = SlashRegistry.new
      @state_refs              = {}
      @on_submit_handler       = nil
      @on_tab_handler          = nil
      @on_start_handlers       = []
      @on_quit_handlers        = []
      @info_blocks             = []
      @info_registration_counter = 0
      @status_row_blocks       = []
      @spinner_label_block     = nil
      @prompt_suggestion_block = nil
      @shortcuts_hint_text     = ""
      @header_config           = {}
      @logger                  = Logger.new($stderr).tap { |l| l.level = Logger::INFO; l.progname = "baslash" }
      @debug_commands_enabled  = false
    end

    # --- ShareableRef ---

    def shareable_ref(name, &block)
      ref = ShareableRef.spawn(name, &block)
      @state_refs[name.to_sym] = ref
      ref
    end

    # --- Header ---

    def header(&block)
      h = HeaderConfig.new
      block.call(h)
      @header_config = h.to_h
    end

    def header_lines
      h = @header_config
      line1_parts = []
      line1_parts << Baslash::Style.color(:cyan, h[:logo].to_s) if h[:logo] && !h[:logo].to_s.empty?
      line1_parts << Baslash::Style.bold(h[:title].to_s)        if h[:title] && !h[:title].to_s.empty?
      line1_parts << Baslash::Style.dim(h[:version].to_s)       if h[:version] && !h[:version].to_s.empty?
      [
        line1_parts.join(" "),
        h[:subtitle] && !h[:subtitle].to_s.empty? ? "  #{Baslash::Style.dim(h[:subtitle].to_s)}" : nil,
        h[:note]     && !h[:note].to_s.empty?     ? "  #{Baslash::Style.dim(h[:note].to_s)}"     : nil
      ].compact.reject { |l| Baslash::Style.strip(l).strip.empty? }
    end

    # --- Style ---

    # No-op stub for backward compatibility with examples that called the
    # curses-era Style.define. Baslash::Style is SGR-based with fixed named
    # styles (NAMED_COLORS, NAMED_STYLES); there is no registration concept.
    # Use Style.apply directly with built-in style names.
    # Task 11 will migrate examples off this API.
    def define_style(name, **opts)
      # intentionally a no-op
    end

    # --- Info bar ---

    def info(name, order: nil, &block)
      @info_registration_counter += 1
      effective_order = order || (10_000 + @info_registration_counter)
      @info_blocks << { name: name.to_sym, order: effective_order, block: block }
    end

    # --- Debug commands opt-in ---

    def enable_debug_commands
      @debug_commands_enabled = true
    end

    def debug_commands_enabled?
      @debug_commands_enabled == true
    end

    def evaluate_info_bar(ctx = nil)
      @info_blocks.sort_by { |b| b[:order] }.map do |b|
        text = (b[:block].call(ctx) rescue nil)
        { key: b[:name], text: text }
      end
    end

    # --- Status rows ---

    def status_row(name, &block)
      @status_row_blocks << { name: name.to_sym, block: block }
    end

    def evaluate_status_rows(ctx = nil)
      @status_row_blocks.map do |b|
        row = StatusRow.new(b[:name])
        (b[:block].call(row, ctx) rescue nil)
        { key: b[:name], segments: row.segments }
      end
    end

    # --- Spinner label ---

    def spinner_label(&block)
      @spinner_label_block = block
    end

    def evaluate_spinner_label(ctx = nil)
      return nil unless @spinner_label_block
      (@spinner_label_block.call(ctx) rescue nil)
    end

    # --- Prompt suggestion ---

    def prompt_suggestion(&block)
      @prompt_suggestion_block = block
    end

    def evaluate_prompt_suggestion(ctx = nil)
      return nil unless @prompt_suggestion_block
      (@prompt_suggestion_block.call(ctx) rescue nil)
    end

    # --- Shortcuts hint ---

    def shortcuts_hint(text = nil)
      @shortcuts_hint_text = text.to_s if text
    end

    # --- Submit / Tab / Start / Quit handlers ---

    # on_submit block signature: |args, ctx| where args = [submitted_line].freeze
    def on_submit(&block)
      @on_submit_handler = Ractor.shareable_proc(&block)
    end

    def on_tab(&block)
      @on_tab_handler = block
    end

    def on_start(&block)
      @on_start_handlers << block
    end

    def on_quit(&block)
      @on_quit_handlers << block
    end

    # --- Slash commands ---

    def slash(name, description: nil, &block)
      @slash_registry.register(name.to_sym, block, description: description)
    end

    # btw DSL: registers /btw slash that calls user block with (question, ctx)
    def btw(&block)
      @slash_registry.register(:btw, proc { |args, ctx|
        question = Array(args).join(" ")
        begin
          answer = block.call(question, ctx)
        rescue StandardError => e
          ctx.logger.error("/btw error: #{e.full_message}") if ctx.respond_to?(:logger)
          next
        end
        ctx.display.append(answer.to_s) if answer && !answer.to_s.empty?
      }, description: "ask a side question (ephemeral)")
    end

    # -----------------------------------------------------------------------
    # Inner structs
    # -----------------------------------------------------------------------

    HeaderConfig = Struct.new(:logo_v, :title_v, :version_v, :subtitle_v, :note_v) do
      def initialize
        super(nil, nil, nil, nil, nil)
      end

      def logo(v = nil);     v.nil? ? @logo_v     : (self.logo_v     = v); end
      def title(v = nil);    v.nil? ? @title_v    : (self.title_v    = v); end
      def version(v = nil);  v.nil? ? @version_v  : (self.version_v  = v); end
      def subtitle(v = nil); v.nil? ? @subtitle_v : (self.subtitle_v = v); end
      def note(v = nil);     v.nil? ? @note_v     : (self.note_v     = v); end

      def to_h
        {
          logo:     logo_v,
          title:    title_v,
          version:  version_v,
          subtitle: subtitle_v,
          note:     note_v
        }.compact
      end
    end

    class StatusRow
      attr_reader :name, :segments

      def initialize(name)
        @name     = name
        @segments = []
      end

      def icon(s);                          @segments << { kind: :icon, text: s }; end
      def text(s);                          @segments << { kind: :text, text: s }; end
      def link(text:, state: nil);          @segments << { kind: :link, text: text, state: state }; end
      def bar(percent:, width: 12);         @segments << { kind: :bar, percent: percent, width: width }; end
    end
  end
end
