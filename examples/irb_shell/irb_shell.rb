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

Cclikesh.run do |shell|
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

  shell.spinner_label do |ctx|
    ctx.state[:phase] == :working ? :auto : nil
  end

  shell.slash(:reset) do |_args, ctx|
    evaluator.reset
    counter.reset
    ctx.display.append("session reset", style: :result)
  end

  shell.slash(:quit) { |_args, ctx| ctx.quit }
  shell.slash(:q)    { |_args, ctx| ctx.quit }
end
