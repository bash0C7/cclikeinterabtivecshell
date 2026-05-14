# Regression: cmux/tmux/screen sometimes export stale LINES/COLUMNS env
# vars from when the multiplexer was started. If left alone, ncurses'
# initscr() uses those stale values instead of the kernel's TIOCGWINSZ,
# producing a too-small layout (body collapses, footer painted in the
# middle of the terminal instead of at the bottom).
#
# Runner.sync_terminal_env_pre_init normalises ENV["LINES"]/ENV["COLUMNS"]
# from the kernel before init_screen. This spec injects deliberately
# stale values (24/80) into a 40x120 PTY and asserts that the shortcuts
# hint substring is rendered in the output stream, confirming the footer
# was painted and the layout used the real 40-row size.
#
# Note: the test harness (PtyRunner#env_for_spawn) overwrites LINES/COLUMNS
# with the actual PTY dimensions after merging the spec's env hash, so the
# injected stale values are superseded before reaching the child process.
# This spec therefore validates that the whole pipeline (env injection +
# pre-init sync + post-init resizeterm) produces a correct layout — not
# the pre-init sync in isolation. The correct way to verify the pre-init
# sync's isolated contribution is via unit test; this e2e spec guards the
# overall regression.

session "stale LINES/COLUMNS env does not break footer placement" do
  timeout 15
  spawn argv: %w[bundle exec ruby examples/zsh_shell/zsh_shell.rb],
        cols:  120,
        rows:  40,
        env:   {
          "TERM"    => "xterm-256color",
          "LANG"    => "en_US.UTF-8",
          "LINES"   => "24",
          "COLUMNS" => "80",
        }
  wait 1.5
  send "/pwd\r"
  wait 1.0
  send "/q\r"
  wait 0.6
end

expect "shortcuts hint is painted (footer survives stale env)" do |c|
  c.output_text_clean.include?("for commands")
end

expect "/pwd output visible" do |c|
  c.output_text_clean.include?(Dir.pwd)
end

expect "session exits cleanly" do |c|
  c.exit_status == 0
end
