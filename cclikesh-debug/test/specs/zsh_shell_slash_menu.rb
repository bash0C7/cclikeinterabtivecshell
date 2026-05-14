# Spec B migration of tmp/longrun/pty_slash.rb.
# Drives examples/zsh_shell/zsh_shell.rb through the slash-menu path
# and asserts that typing "/p" surfaces "/pwd" in the autocomplete
# dialog (the regression fixed at 59315e4).

session "zsh-shell slash menu shows /pwd on /p" do
  timeout 15
  spawn argv: %w[bundle exec ruby examples/zsh_shell/zsh_shell.rb],
        cols:  120,
        rows:  30,
        env:   { "TERM" => "xterm-256color", "LANG" => "en_US.UTF-8" }
  wait 1.0
  send "/"
  wait 1.0
  send "p"
  wait 1.0
  send "\b\b"
  send "/q\n"
  wait 0.5
end

expect "menu lists /pwd after typing /" do |c|
  c.contains?("/pwd")
end

expect "menu lists /help after typing /" do |c|
  c.contains?("/help")
end

expect "session exits cleanly" do |c|
  c.exit_status == 0
end
