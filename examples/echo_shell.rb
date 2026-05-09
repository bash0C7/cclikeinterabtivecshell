# frozen_string_literal: true

require "cclikesh"

input_path = ARGV[0] || raise("usage: echo_shell.rb <input_path> <output_path>")
output_path = ARGV[1] || raise("usage: echo_shell.rb <input_path> <output_path>")

Cclikesh.run(input_path: input_path, output_path: output_path) do |shell|
  shell.on_submit do |line, ctx|
    ctx.display.append("you said: #{line}")
  end

  shell.slash(:quit) { |_args, ctx| ctx.quit }
end

puts "shell exited; output written to #{output_path}"
