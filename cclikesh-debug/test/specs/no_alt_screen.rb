session "zsh_shell-no-alt-screen" do
  timeout 8.0
  spawn argv: ["bundle", "exec", "ruby", "examples/zsh_shell/zsh_shell.rb"],
        cols: 80, rows: 24, env: { "TERM" => "xterm-256color" }
  wait 1.5
  send "/q\n"
  wait 0.5
end

expect("no \\e[?1049h (smcup) in captured output") do |c|
  !c.output_bytes.include?("\e[?1049h")
end

expect("session exits cleanly") do |c|
  c.exit_status == 0
end
