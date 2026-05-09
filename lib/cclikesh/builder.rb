# frozen_string_literal: true

require "logger"

module Cclikesh
  class Builder
    LOG_LEVELS = {
      debug: Logger::DEBUG, info: Logger::INFO,
      warn: Logger::WARN, error: Logger::ERROR, fatal: Logger::FATAL
    }.freeze

    attr_reader :on_submit_handler, :on_state_change_handler, :slash_handlers, :on_start_handlers, :on_quit_handlers, :logger

    def initialize
      @on_submit_handler = nil
      @on_state_change_handler = nil
      @slash_handlers = {}
      @on_start_handlers = []
      @on_quit_handlers = []
      @styles = {}
      @logger = Logger.new($stderr)
      @logger.level = Logger::INFO
      @logger.progname = "cclikesh"
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
  end
end
