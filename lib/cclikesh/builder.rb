# frozen_string_literal: true

require "logger"

module Cclikesh
  class Builder
    LOG_LEVELS = {
      debug: Logger::DEBUG, info: Logger::INFO,
      warn: Logger::WARN, error: Logger::ERROR, fatal: Logger::FATAL
    }.freeze

    attr_reader :on_submit_handler, :on_state_change_handler, :slash_handlers, :on_start_handlers, :on_quit_handlers, :before_submit_handlers, :after_submit_handlers, :on_tab_handler, :before_tab_handlers, :after_tab_handlers, :logger
    attr_reader :spinner_frames, :spinner_colors, :spinner_frame_interval, :spinner_label_proc, :idle_phrase_interval
    attr_accessor :tick_interval, :idle_phrases

    SpinnerConfigurator = Struct.new(:frames, :colors, :frame_interval)

    def initialize
      @on_submit_handler = nil
      @on_state_change_handler = nil
      @slash_handlers = {}
      @on_start_handlers = []
      @on_quit_handlers = []
      @before_submit_handlers = []
      @after_submit_handlers = []
      @on_tab_handler = nil
      @before_tab_handlers = []
      @after_tab_handlers = []
      @styles = {}
      @logger = Logger.new($stderr)
      @logger.level = Logger::INFO
      @logger.progname = "cclikesh"
      @tick_interval = 0.06
      @spinner_frames = %w[✻ ✶ ✷ ✸ ✹]
      @spinner_colors = [:cyan, :magenta]
      @spinner_frame_interval = 0.15
      @spinner_label_proc = nil
      @idle_phrases = load_default_idle_phrases
      @idle_phrase_interval = 3.0
      @info_segments = []
      @info_registration_counter = 0
    end

    def on_submit(&block)
      @on_submit_handler = block
    end

    def on_state_change(&block)
      @on_state_change_handler = block
    end

    def on_start(&block)
      @on_start_handlers << block
    end

    def on_quit(&block)
      @on_quit_handlers << block
    end

    def before_submit(&block)
      @before_submit_handlers << block
    end

    def after_submit(&block)
      @after_submit_handlers << block
    end

    def on_tab(&block)
      @on_tab_handler = block
    end

    def before_tab(&block)
      @before_tab_handlers << block
    end

    def after_tab(&block)
      @after_tab_handlers << block
    end

    def slash(name, &block)
      @slash_handlers[name.to_sym] = block
    end

    def slash_handler(name)
      @slash_handlers[name.to_sym]
    end

    def define_style(name, **opts)
      @styles[name.to_sym] = opts
    end

    def style_definition(name)
      @styles[name.to_sym]
    end

    def logger=(other)
      @logger = other
    end

    def log_level=(sym)
      level = LOG_LEVELS[sym.to_sym]
      raise ArgumentError, "unknown log level: #{sym.inspect}" unless level
      @logger.level = level
    end

    def log_to(target)
      prev_level = @logger.level
      @logger = case target
                when IO, StringIO then Logger.new(target)
                when String       then Logger.new(target)
                else raise ArgumentError, "log_to expects IO or path String, got #{target.class}"
                end
      @logger.level    = prev_level
      @logger.progname = "cclikesh"
    end

    def spinner
      cfg = SpinnerConfigurator.new(@spinner_frames, @spinner_colors, @spinner_frame_interval)
      yield cfg
      @spinner_frames = cfg.frames
      @spinner_colors = cfg.colors
      @spinner_frame_interval = cfg.frame_interval
    end

    def spinner_label(&block)
      @spinner_label_proc = block
    end

    def idle_phrase_interval=(v)
      @idle_phrase_interval = v
    end

    def info(name, order: nil, &block)
      @info_registration_counter += 1
      effective_order = order || (10_000 + @info_registration_counter)
      @info_segments << [name.to_sym, effective_order, block]
    end

    def info_segments
      @info_segments.sort_by { |_, order, _| order }
    end

    private

    def load_default_idle_phrases
      path = File.expand_path("idle_phrases.txt", __dir__)
      File.readlines(path, chomp: true).reject(&:empty?)
    end
  end
end
