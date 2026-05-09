# frozen_string_literal: true

require "cclikesh"

Cclikesh.run do |shell|
  shell.define_style(:warn, fg: :yellow, bold: true)

  shell.on_submit do |line, ctx|
    ctx.display.append("you said: #{line}", style: :result)
  end

  shell.slash(:slow) do |_args, ctx|
    ctx.display.open_live(style: :thinking) do |slot|
      3.times do |i|
        sleep 0.1
        slot.update("Roosting... #{i + 1}/3")
      end
    end
    ctx.display.append("done", style: :result)
  end

  shell.slash(:warn) do |args, ctx|
    ctx.display.append(args.join(" "), style: :warn)
  end

  shell.slash(:quit) do |_args, ctx|
    ctx.quit
  end
end
