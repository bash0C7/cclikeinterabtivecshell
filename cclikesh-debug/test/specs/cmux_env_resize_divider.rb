# cclikesh-debug/test/specs/cmux_env_resize_divider.rb
#
# R3: Resize does not reflow dividers to the new terminal width. Reproduced
# under cmux-like env by opting into clear_size_env: true and firing a real
# SIGWINCH via script_resize to a wider size.

session "resize widens dividers to match new cols" do
  timeout 15
  spawn argv: %w[bundle exec ruby examples/zsh_shell/zsh_shell.rb],
        cols:  80,
        rows:  24,
        env:   { "TERM" => "xterm-256color", "LANG" => "en_US.UTF-8" },
        clear_size_env: true
  wait 1.5
  send "\r"          # harmless input; ensures the read loop has run at least once
  wait 0.4
  resize 120, 30
  wait 0.8           # let SIGWINCH propagate + Chrome.handle_resize complete
  send "/q\r"
  wait 0.6
end

expect "post-resize Chrome.draw_dividers sees cols=120, lines=30" do |c|
  draw_entries = c.diag_entries.select { |e| e[:tag] == "Chrome.draw_dividers" }
  next false if draw_entries.empty?
  last = draw_entries.last
  last[:cols] == 120 && last[:lines] == 30
end

expect "Chrome.handle_resize.after_resizeterm winsize is [30, 120]" do |c|
  rs = c.diag_entries.select { |e| e[:tag] == "Chrome.handle_resize.after_resizeterm" }
  next false if rs.empty?
  rs.last[:winsize] == [30, 120]
end

# Byte: locate the divider redraw after resize. The divider is drawn via
# ACS_HLINE (A_ALTCHARSET | 0x71). On stock xterm-style terminfo, ncurses
# brackets the run with SO/SI (\e(0 ... \e(B). We accept either bracketed
# or unbracketed forms by counting the 'q' bytes in the run after stripping
# the optional SO/SI brackets.
expect "divider after resize spans the new cols (120 cells, not 80)" do |c|
  resize_entries = c.diag_entries.select { |e| e[:tag] == "Chrome.handle_resize.after_resizeterm" }
  next false if resize_entries.empty?
  post_resize_lines = resize_entries.last[:lines]
  next false unless post_resize_lines.is_a?(Integer)
  divider_row_top    = post_resize_lines - 3 - 3  # lines - FOOTER_HEIGHT - 3, 0-based
  divider_row_bottom = post_resize_lines - 3 - 1  # lines - FOOTER_HEIGHT - 1, 0-based
  candidates = [divider_row_top + 1, divider_row_bottom + 1]   # convert to 1-based for CUP

  bytes = c.output_bytes
  found_widths = []
  candidates.each do |row|
    cup_pattern = "\e[#{row};1H".b
    last_cup = bytes.b.rindex(cup_pattern)
    next unless last_cup
    slice = bytes.byteslice(last_cup + cup_pattern.bytesize, 400)
    slice = slice.sub(/\A\e\(0/, "")  # strip optional SO
    run = slice[/\Aq+/] || ""         # count contiguous q runs
    found_widths << run.length
  end
  found_widths.any? { |w| w == 120 } && !found_widths.any? { |w| w == 80 }
end

expect "session exits cleanly" do |c|
  c.exit_status == 0
end
