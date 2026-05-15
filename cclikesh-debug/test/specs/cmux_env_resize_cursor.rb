# cclikesh-debug/test/specs/cmux_env_resize_cursor.rb
#
# R1: After typing a slash command and resizing, the visible cursor lands
# inside the body text instead of on the prompt row. Reproduced under
# cmux-like env (LINES/COLUMNS unset in the child) by opting into
# clear_size_env: true and firing a real SIGWINCH via script_resize.

session "resize after slash command parks cursor on prompt row" do
  timeout 15
  spawn argv: %w[bundle exec ruby examples/zsh_shell/zsh_shell.rb],
        cols:  80,
        rows:  24,
        env:   { "TERM" => "xterm-256color", "LANG" => "en_US.UTF-8" },
        clear_size_env: true
  wait 1.5
  send "/heko\r"
  wait 0.8
  resize 80, 40
  wait 0.8
  send "\x03"   # Ctrl-C to clear any half-typed prompt buffer
  wait 0.3
  send "/q\r"
  wait 0.6
end

# The post-resize Chrome.handle_resize.after_resizeterm entry tells us the
# new curses.lines value. The prompt row is at lines - FOOTER_HEIGHT - 1
# (1-based, see Runner.park_cursor_on_prompt_row).
expect "post-resize handle_resize entry sees the new size" do |c|
  resize_entries = c.diag_entries.select { |e| e[:tag] == "Chrome.handle_resize.after_resizeterm" }
  !resize_entries.empty? && resize_entries.last[:lines] == 40 && resize_entries.last[:cols] == 80
end

expect "final cursor placement is on the prompt row" do |c|
  resize_entries = c.diag_entries.select { |e| e[:tag] == "Chrome.handle_resize.after_resizeterm" }
  next false if resize_entries.empty?
  final_lines = resize_entries.last[:lines]
  footer_h = 3  # mirrors Cclikesh::Chrome::FOOTER_HEIGHT
  expected_row = final_lines - footer_h - 1   # 1-based row from park_cursor_on_prompt_row

  cups = c.output_bytes.scan(/\e\[(\d+);(\d+)H/).map { |r, col| [r.to_i, col.to_i] }
  next false if cups.empty?
  final_cup = cups.last
  final_cup[0] == expected_row
end

expect "session exits cleanly" do |c|
  c.exit_status == 0
end
