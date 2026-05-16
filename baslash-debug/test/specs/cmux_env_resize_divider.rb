# baslash-debug/test/specs/cmux_env_resize_divider.rb
#
# R3: Resize does not reflow dividers to the new terminal width. Reproduced
# under cmux-like env by opting into clear_size_env: true and firing a real
# SIGWINCH via script_resize to a wider size.

# Count visible 'q' cells (DEC line drawing horizontal bar) in a divider run,
# expanding REP escapes (\e[Nb) that ncurses emits to compress runs of repeated
# characters. ncurses commonly outputs a 120-cell divider as `q\e[118bq` rather
# than 120 literal q bytes, and may interleave SGR resets like `\e[0m` between
# the SCS-G0 enter (`\e(0`) and the q run. Stops at \e(B (exit DEC) or any
# other non-q non-handled byte.
count_dec_cells = lambda do |slice|
  s = slice.b.dup
  s = s.sub(/\A\e\(0/, "")                      # strip enter DEC graphics
  count = 0
  loop do
    if (m = s.match(/\A\e\[[0-9;]*m/))          # SGR (color/attr) — no cell
      s = s[m[0].length..]
      next
    end
    if s.start_with?("q")
      count += 1
      s = s[1..]
      next
    end
    if (m = s.match(/\A\e\[(\d+)b/)) && count > 0  # REP — repeat preceding char
      count += m[1].to_i
      s = s[m[0].length..]
      next
    end
    break
  end
  count
end

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
# brackets the run with SO/SI (\e(0 ... \e(B) and may emit REP (\e[Nb) to
# compress repeated q's. count_dec_cells handles both bracketing and REP.
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
    found_widths << count_dec_cells.call(slice)
  end
  found_widths.any? { |w| w == 120 } && !found_widths.any? { |w| w == 80 }
end

expect "session exits cleanly" do |c|
  c.exit_status == 0
end
