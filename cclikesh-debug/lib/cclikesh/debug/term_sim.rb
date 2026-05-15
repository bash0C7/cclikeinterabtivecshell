# frozen_string_literal: true

module Cclikesh
  module Debug
    # Minimal terminal emulator used to verify the *visible* state produced
    # by a captured PTY byte stream. Tracks cursor position, DECSC/DECRC
    # saved cursor, DECSTBM scroll region, and a fixed-size grid of cells.
    #
    # Implements just enough VT100/xterm to render cclikesh output correctly:
    # printable bytes, CR / LF / BS, IND / RI / NEL, CUP / CHA / VPA / CUU
    # / CUD / CUF / CUB, EL / ED, IL / DL, SU / SD, REP, DECSTBM, DECSC /
    # DECRC, SCS-G0 (ASCII <-> DEC graphics). Mode set/reset (`\e[?Nh/l`),
    # SGR (`\e[Nm`), DSR queries, and OSC / DCS sequences are silently
    # consumed but do not affect the grid.
    #
    # Use cases: spec assertions that need to know "what row did the prompt
    # land on" without depending on a real terminal. Not a full emulator.
    class TermSim
      attr_reader :rows, :cols, :grid, :row, :col, :scroll_top, :scroll_bottom

      def initialize(rows, cols)
        @rows = rows
        @cols = cols
        @grid = Array.new(rows) { " " * cols }
        @row = 1
        @col = 1
        @saved_row = 1
        @saved_col = 1
        @scroll_top = 1
        @scroll_bottom = rows
        @charset_g0 = :ascii
        @prev_printable = nil
      end

      def feed(bytes)
        s = bytes.b.dup
        until s.empty?
          if s.start_with?("\e")
            consumed = handle_esc(s)
            s = s[consumed..]
          elsif s.start_with?("\r")
            @col = 1
            s = s[1..]
          elsif s.start_with?("\n")
            cursor_down_with_scroll
            s = s[1..]
          elsif s.start_with?("\b")
            @col -= 1 if @col > 1
            s = s[1..]
          elsif (b = s.bytes.first) && b < 0x20
            # Other C0 control bytes — silently consume.
            s = s[1..]
          else
            ch = s[0]
            ch = "─" if @charset_g0 == :dec_graphics && ch == "q"
            write_at_cursor(ch)
            @prev_printable = s[0]
            s = s[1..]
          end
        end
      end

      # Returns the 1-based row index of the first row whose rendered
      # content matches `query` (String for substring, Regexp for match),
      # or nil if no row matches.
      def find_row(query)
        @grid.each_with_index do |line, i|
          if query.is_a?(Regexp)
            return i + 1 if query.match?(line)
          else
            return i + 1 if line.include?(query.to_s)
          end
        end
        nil
      end

      private

      def write_at_cursor(ch)
        if @col > @cols
          cursor_down_with_scroll
          @col = 1
        end
        @grid[@row - 1][@col - 1] = ch
        @col += 1
      end

      def cursor_down_with_scroll
        if @row == @scroll_bottom
          @grid[(@scroll_top - 1)...(@scroll_bottom - 1)] = @grid[@scroll_top...@scroll_bottom]
          @grid[@scroll_bottom - 1] = " " * @cols
        elsif @row < @rows
          @row += 1
        end
      end

      def handle_esc(s)
        return handle_decsc       if s.start_with?("\e7")
        return handle_decrc       if s.start_with?("\e8")
        return handle_g0_dec      if s.start_with?("\e(0")
        return handle_g0_ascii    if s.start_with?("\e(B")
        return handle_index       if s.start_with?("\eD")
        return handle_reverse_index if s.start_with?("\eM")
        return handle_nel         if s.start_with?("\eE")

        if (m = s.match(/\A\e\[([?>]?)([\d;]*)([A-Za-z@`{|}~])/))
          handle_csi(m[1], m[2], m[3])
          return m[0].length
        end

        # OSC: \e] ... BEL or ST. Consume up to terminator.
        if s.start_with?("\e]")
          if (m = s.match(/\A\e\][^\a\e]*(?:\a|\e\\)/m))
            return m[0].length
          end
        end
        # DCS / SOS / PM / APC: \eP / \eX / \e^ / \e_ ... ST
        if s[1] && %w[P X ^ _].include?(s[1])
          if (m = s.match(/\A\e[PX^_].*?\e\\/m))
            return m[0].length
          end
        end

        1
      end

      def handle_decsc
        @saved_row, @saved_col = @row, @col
        2
      end

      def handle_decrc
        @row, @col = @saved_row, @saved_col
        2
      end

      def handle_g0_dec
        @charset_g0 = :dec_graphics
        3
      end

      def handle_g0_ascii
        @charset_g0 = :ascii
        3
      end

      def handle_index
        cursor_down_with_scroll
        2
      end

      def handle_reverse_index
        if @row == @scroll_top
          @grid[@scroll_top...@scroll_bottom] = @grid[(@scroll_top - 1)...(@scroll_bottom - 1)]
          @grid[@scroll_top - 1] = " " * @cols
        elsif @row > 1
          @row -= 1
        end
        2
      end

      def handle_nel
        @col = 1
        cursor_down_with_scroll
        2
      end

      def handle_csi(_priv, params, final)
        args = params.split(";").map { |p| p.empty? ? nil : p.to_i }
        case final
        when "H", "f"
          @row = clamp(args[0] || 1, 1, @rows)
          @col = clamp(args[1] || 1, 1, @cols)
        when "A"
          @row = clamp(@row - (args[0] || 1), 1, @rows)
        when "B"
          @row = clamp(@row + (args[0] || 1), 1, @rows)
        when "C"
          @col = clamp(@col + (args[0] || 1), 1, @cols)
        when "D"
          @col = clamp(@col - (args[0] || 1), 1, @cols)
        when "G"
          @col = clamp(args[0] || 1, 1, @cols)
        when "d"
          @row = clamp(args[0] || 1, 1, @rows)
        when "r"
          @scroll_top    = clamp(args[0] || 1,    1, @rows)
          @scroll_bottom = clamp(args[1] || @rows, 1, @rows)
          @row, @col = 1, 1
        when "K"
          erase_in_line(args[0] || 0)
        when "J"
          erase_in_display(args[0] || 0)
        when "b"
          n = args[0] || 1
          ch = @prev_printable
          if ch
            mapped = (@charset_g0 == :dec_graphics && ch == "q") ? "─" : ch
            n.times { write_at_cursor(mapped) }
          end
        when "L"
          insert_lines(args[0] || 1)
        when "M"
          delete_lines(args[0] || 1)
        when "S"
          scroll_up(args[0] || 1)
        when "T"
          scroll_down(args[0] || 1)
        else
          # SGR (m), DSR (n), modes (h/l), unhandled — no display effect.
        end
      end

      def erase_in_line(mode)
        case mode
        when 0 then @grid[@row - 1][(@col - 1)..] = " " * (@cols - @col + 1)
        when 1 then @grid[@row - 1][0..(@col - 1)] = " " * @col
        when 2 then @grid[@row - 1] = " " * @cols
        end
      end

      def erase_in_display(mode)
        case mode
        when 0
          @grid[@row - 1][(@col - 1)..] = " " * (@cols - @col + 1)
          ((@row)..(@rows - 1)).each { |r| @grid[r] = " " * @cols }
        when 1
          @grid[@row - 1][0..(@col - 1)] = " " * @col
          (0..(@row - 2)).each { |r| @grid[r] = " " * @cols }
        when 2, 3
          @grid.each_index { |r| @grid[r] = " " * @cols }
        end
      end

      def insert_lines(n)
        return unless @row >= @scroll_top && @row <= @scroll_bottom
        n.times do
          @grid[@row...@scroll_bottom] = @grid[(@row - 1)...(@scroll_bottom - 1)]
          @grid[@row - 1] = " " * @cols
        end
      end

      def delete_lines(n)
        return unless @row >= @scroll_top && @row <= @scroll_bottom
        n.times do
          @grid[(@row - 1)...(@scroll_bottom - 1)] = @grid[@row...@scroll_bottom]
          @grid[@scroll_bottom - 1] = " " * @cols
        end
      end

      def scroll_up(n)
        n.times do
          @grid[(@scroll_top - 1)...(@scroll_bottom - 1)] = @grid[@scroll_top...@scroll_bottom]
          @grid[@scroll_bottom - 1] = " " * @cols
        end
      end

      def scroll_down(n)
        n.times do
          @grid[@scroll_top...@scroll_bottom] = @grid[(@scroll_top - 1)...(@scroll_bottom - 1)]
          @grid[@scroll_top - 1] = " " * @cols
        end
      end

      def clamp(v, lo, hi)
        [[v, lo].max, hi].min
      end
    end
  end
end
