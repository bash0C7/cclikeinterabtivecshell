# Regression for Spec 2026-05-14-curses-noalt-redesign.
# Asserts that the terminfo overlay successfully prevents curses from
# entering the alt-screen: the recorded byte stream from booting
# zsh_shell.rb and quitting must contain zero \e[?1049h and \e[?1049l.

session "zsh-shell never enters the alt-screen" do
  timeout 15
  spawn argv: %w[bundle exec ruby examples/zsh_shell/zsh_shell.rb],
        cols:  120,
        rows:  30,
        # xterm-256color is a standard entry that has smcup/rmcup, so
        # we can prove the overlay works by stripping them.
        env:   { "TERM" => "xterm-256color", "LANG" => "en_US.UTF-8" }
  wait 1.5
  send "/q\r"
  wait 0.8
end

expect "session emits no smcup (alt-screen enter)" do |c|
  !c.contains?("\e[?1049h")
end

expect "session emits no rmcup (alt-screen leave)" do |c|
  !c.contains?("\e[?1049l")
end

expect "session exits cleanly" do |c|
  c.exit_status == 0
end
