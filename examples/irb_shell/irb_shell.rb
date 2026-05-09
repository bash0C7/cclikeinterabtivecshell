# frozen_string_literal: true

require "cclikesh"
require_relative "irb_evaluator"
require_relative "irb_completer"
require_relative "byte_counter"

def format_duration(sec)
  m, s = sec.divmod(60)
  m.zero? ? "#{s.to_i}s" : "#{m.to_i}m #{s.to_i}s"
end

evaluator = IrbEvaluator.new
completer = IrbCompleter.new(evaluator.binding)
counter   = ByteCounter.new
start_at  = Time.now
SESSION_BUDGET_BYTES = 8 * 1024

Cclikesh.run do |shell|
  shell.header do |h|
    h.logo     "✻"
    h.title    "cclikesh"
    h.version  "v#{Cclikesh::VERSION}"
    h.subtitle "Ruby #{RUBY_VERSION} · #{Dir.pwd}"
    h.note     "irb on cclikesh · /q to exit · /reset to clear bindings"
  end

  shell.on_submit do |line, ctx|
    ctx.display.append(line, prompt: "irb(main)> ")
    counter.add(line.bytesize)

    ctx.state[:phase] = :working
    slot = ctx.display.open_live(style: :thinking)
    slot.update("evaluating...")

    begin
      result = evaluator.evaluate(line)
      slot.commit
      ctx.display.append("=> #{result.inspect}", style: :result)
      counter.add(result.inspect.bytesize)
    rescue ScriptError, StandardError => e
      slot.discard
      ctx.display.append("#{e.class}: #{e.message}", style: :error)
      ctx.logger.error(e.full_message)
    ensure
      ctx.state[:phase] = :idle
    end
  end

  shell.on_tab do |buf, pos, ctx|
    candidates = completer.candidates(buf, pos)
    ctx.dialog.show(candidates.join("\n")) if candidates.size > 1
    candidates
  end

  shell.info(:elapsed, order: 10) { |_| format_duration(Time.now - start_at) }
  shell.info(:tokens,  order: 20) { |_| "↓ #{counter.human}" }

  shell.status_row :usage do |row, _ctx|
    pct = [counter.bytes * 100.0 / SESSION_BUDGET_BYTES, 100].min
    row.bar percent: pct, width: 12
    row.text Time.now.strftime("%H:%M")
    row.link text: "main", state: :gray
  end

  shell.spinner_label do |ctx|
    ctx.state[:phase] == :working ? :auto : nil
  end

  shell.prompt_suggestion do |ctx|
    ctx.state[:phase] == :idle ? "puts 'hello, cclikesh'" : nil
  end

  shell.shortcuts_hint "? for shortcuts · /transcript to save log · /reset · /q to quit"

  shell.btw do |question, _ctx|
    "(no AI hooked up — you asked: #{question})"
  end

  shell.slash(:reset, description: "reset irb session") do |_args, ctx|
    evaluator.reset
    counter.reset
    ctx.display.append("session reset", style: :result)
  end

  shell.slash(:quit, description: "exit") { |_args, ctx| ctx.quit }
  shell.slash(:q,    description: "exit") { |_args, ctx| ctx.quit }
end
