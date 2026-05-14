session "zsh_shell-dividers-inline" do
  timeout 8.0
  spawn argv: ["bundle", "exec", "ruby", "examples/zsh_shell/zsh_shell.rb"],
        cols: 80, rows: 24, env: { "TERM" => "xterm-256color" }
  wait 1.5
  send "/q\n"
  wait 0.5
end

expect("captured output contains divider runs") do |c|
  c.output_bytes.scan(/(?:\xE2\x94\x80){6,}/n).length >= 2
end

expect("session exits cleanly") do |c|
  c.exit_status == 0
end
