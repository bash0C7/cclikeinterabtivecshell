# frozen_string_literal: true

require "cclikesh"

Cclikesh.run do |shell|
  shell.on_submit do |line, ctx|
    ctx.display.append("you said: #{line}")
  end

  shell.slash(:quit) do |_args, ctx|
    ctx.quit
  end
end
