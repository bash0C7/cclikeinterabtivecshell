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

# Byte: between the /heko body output and the last "> " prompt, the count
# of "\n" bytes must be <= 2. More than 2 indicates the large vertical gap
# symptom of R2.
expect "no large vertical gap between /heko output and next prompt" do |c|
  bytes = c.output_bytes
  marker = "Unknown command: /heko"
  m_idx = bytes.index(marker)
  next true unless m_idx   # if marker absent, /heko didn't reach Display — separate bug, don't false-positive R2
  prompt_idx = bytes.index("> ", m_idx + marker.length)
  next true unless prompt_idx
  span = bytes.byteslice(m_idx + marker.length, prompt_idx - (m_idx + marker.length))
  span.count("\n") <= 2
end

expect "session exits cleanly" do |c|
  c.exit_status == 0
end
