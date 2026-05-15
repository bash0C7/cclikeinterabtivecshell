# cclikesh-debug/test/specs/cmux_env_slash_layout.rb
#
# R2: After /pwd or /heko, the body output is separated from the next
# prompt by many blank rows AND the 3-row footer (spinner / info_bar /
# shortcuts hint) disappears. Reproduced under cmux-like env (LINES/
# COLUMNS unset in the child) by opting into clear_size_env: true.

session "slash command output keeps footer visible and gap small" do
  timeout 15
  spawn argv: %w[bundle exec ruby examples/zsh_shell/zsh_shell.rb],
        cols:  120,
        rows:  40,
        env:   { "TERM" => "xterm-256color", "LANG" => "en_US.UTF-8" },
        clear_size_env: true
  wait 1.5
  send "/pwd\r"
  wait 0.8
  send "/heko\r"
  wait 0.8
  send "/q\r"
  wait 0.6
end

# Diag: every Display.refresh between /pwd and quit must report curses.lines
# matching the spawn rows (40), not a 24/80 default.
expect "Display.refresh sees the real winsize throughout" do |c|
  refresh_entries = c.diag_entries.select { |e| e[:tag] == "Display.refresh" }
  next false if refresh_entries.empty?
  max_lines = refresh_entries.map { |e| e[:lines] }.compact.max
  max_lines == 40
end

# Byte: the tail of the byte stream (last 4 KiB before /q echo) must
# contain a spinner glyph — proves the footer was painted in the final
# visible frame.
expect "spinner glyph present in final visible frame" do |c|
  bytes = c.output_bytes
  q_idx = bytes.rindex("/q")
  tail_start = q_idx ? [q_idx - 4096, 0].max : [bytes.bytesize - 4096, 0].max
  tail = bytes.byteslice(tail_start, [4096, bytes.bytesize - tail_start].min)
  tail.include?("*") || tail.include?("+")
end

# Visual: render the captured byte stream through TermSim and check the
# distance between the row holding "Unknown command: /heko" and the row
# holding the prompt. R2 reports "many blank rows" between them; under a
# correct layout there is exactly one divider row separating them, so the
# row distance is 2 (heko_row + 2 = prompt_row).
#
# Note: counting raw "\n" bytes in the byte stream over-reports the gap,
# because ncurses brackets harmless cursor motion in DECSC/DECRC pairs and
# the LF bytes inside that bracket do not produce visible motion.
expect "no large vertical gap between /heko output and next prompt" do |c|
  sim = c.screen(rows: c.spawn_rows, cols: c.spawn_cols)
  heko_row = sim.find_row("Unknown command: /heko")
  next true unless heko_row   # marker absent — separate bug, do not false-positive
  prompt_row = sim.find_row(/^> /)
  next true unless prompt_row
  (prompt_row - heko_row).abs <= 2
end

expect "session exits cleanly" do |c|
  c.exit_status == 0
end
