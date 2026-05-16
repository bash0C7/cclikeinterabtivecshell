# Regression for Spec 2026-05-14-curses-noalt-redesign.
#
# Asserts that command output reaches the recorded byte stream when
# running under the no-alt-screen overlay — i.e. that curses keeps
# painting the body region after the overlay relocates TERM/TERMINFO_DIRS.
# Complements no_alt_screen.rb (which only checks for absence of
# smcup/rmcup) with a positive-paint assertion.

session "command output reaches the body region" do
  timeout 15
  spawn argv: %w[bundle exec ruby examples/zsh_shell/zsh_shell.rb],
        cols:  120,
        rows:  30,
        env:   { "TERM" => "xterm-256color", "LANG" => "en_US.UTF-8" }
  wait 1.5
  send "/pwd\r"
  wait 1.2
  send "/q\r"
  wait 0.8
end

expect "/pwd output (current working directory) appears in the recorded stream" do |c|
  # `output_text_clean` strips CSI/OSC/DECSC escapes so curses cursor
  # moves and SGR don't fragment the path string we're looking for.
  c.output_text_clean.include?(Dir.pwd)
end

expect "the shortcuts hint is visible in the recorded stream" do |c|
  # Sanity check that the chrome rendered — if curses crashed silently
  # before painting the footer, this would fail.
  c.output_text_clean.include?("for commands")
end

expect "session exits cleanly" do |c|
  c.exit_status == 0
end
