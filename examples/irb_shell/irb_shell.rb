# frozen_string_literal: true

require "baslash"
require_relative "irb_evaluator"
require_relative "irb_completer"
require_relative "byte_counter"

start_at = Time.now.freeze
SESSION_BUDGET_BYTES = 8 * 1024

Baslash.run do |shell|
  shell.state(:evaluator) { IrbEvaluator.new }
  shell.state(:counter)   { ByteCounter.new }

  shell.header do |h|
    h.logo     "✻"
    h.title    "baslash"
    h.version  "v#{Baslash::VERSION}"
    h.subtitle "Ruby #{RUBY_VERSION} · #{Dir.pwd}"
    h.note     "irb on baslash · /q to exit · /reset to clear bindings"
  end

  shell.on_submit do |args, ctx|
    line = args.first
    ctx.display.append("irb(main)> #{line}")
    ctx.state[:counter].add(line.bytesize)

    ctx.state[:phase] = :working
    slot = ctx.display.open_live(style: :thinking)
    slot.update("evaluating...")
    begin
      result = ctx.state[:evaluator].evaluate(line)
      slot.commit
      ctx.display.append("=> #{result.inspect}", style: :result)
      ctx.state[:counter].add(result.inspect.bytesize)
    rescue ScriptError, StandardError => e
      slot.discard
      ctx.display.append("#{e.class}: #{e.message}", style: :error)
      ctx.logger.error(e.full_message)
    ensure
      ctx.state[:phase] = :idle
    end
  end

  shell.info(:elapsed, order: 10) do |_|
    sec = (Time.now - start_at).to_i
    m, s = sec.divmod(60)
    m.zero? ? "#{s}s" : "#{m}m #{s}s"
  end

  shell.spinner_label { |_| :auto }
  shell.shortcuts_hint "? for shortcuts · /transcript to save log · /reset · /q to quit"

  shell.btw do |question, _ctx|
    "(no AI hooked up — you asked: #{question})"
  end

  shell.slash(:reset, description: "reset irb session") do |_args, ctx|
    ctx.state[:evaluator].reset
    ctx.state[:counter].reset
    ctx.display.append("session reset", style: :result)
  end

  shell.slash(:quit, description: "exit") { |_args, ctx| ctx.quit }
  shell.slash(:q,    description: "exit") { |_args, ctx| ctx.quit }
end
