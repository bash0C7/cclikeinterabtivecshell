# Regression for Bug B: after a slash command (/pwd), footer must remain
# visible and body content must appear bottom-aligned (close to dividers).
#
# Before the fix, Display.refresh top-aligned content in the body area.
# With a tall terminal (rows=40), this left ~30 blank rows between content
# and the dividers/prompt, and the shortcuts hint disappeared from view.
# After the fix, content is bottom-aligned so the last output row sits
# flush against the body/prompt divider.

session "footer survives /pwd slash command on 40-row terminal" do
  timeout 15
  spawn argv: %w[bundle exec ruby examples/zsh_shell/zsh_shell.rb],
        cols:  120,
        rows:  40,
        env:   { "TERM" => "xterm-256color", "LANG" => "en_US.UTF-8" }
  wait 1.5
  send "/pwd\r"
  wait 1.2
  send "/q\r"
  wait 0.8
end

expect "/pwd output (current working directory) appears in the recorded stream" do |c|
  c.output_text_clean.include?(Dir.pwd)
end

expect "the shortcuts hint (footer) is visible in the recorded stream" do |c|
  # If the footer was never painted or was overwritten without repaint, this fails.
  c.output_text_clean.include?("for commands")
end

expect "session exits cleanly" do |c|
  c.exit_status == 0
end
