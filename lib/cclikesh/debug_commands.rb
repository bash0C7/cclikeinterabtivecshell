# frozen_string_literal: true

module Cclikesh
  module DebugCommands
    USAGE_SLEEP = "usage: /debug-sleep N  (0 < N <= 60)".freeze
    USAGE_EMIT  = "usage: /debug-emit STRING  (\\e, \\xNN, \\n, \\r, \\t, \\\\)".freeze
    SLEEP_MAX = 60.0

    def self.register(registry, runtime_state = {})
      register_sleep(registry)
      register_emit(registry)
      register_color_probe(registry)
      register_tick_counter(registry, runtime_state)
      register_terminal_caps(registry)
      register_snapshot(registry)
      register_frame_dump(registry)
    end

    def self.parse_sleep_arg(raw)
      return nil if raw.nil? || raw.empty?
      n = Float(raw) rescue nil
      return nil if n.nil?
      return nil if n <= 0 || n > SLEEP_MAX
      n
    end

    def self.register_sleep(registry)
      registry.register(:"debug-sleep", ->(args, ctx) {
        n = Cclikesh::DebugCommands.parse_sleep_arg(args.first)
        if n.nil?
          ctx.display.append(USAGE_SLEEP, style: :error)
          next
        end
        ctx.state[:phase] = :working
        sleep n
        ctx.state[:phase] = :idle
      }, description: "force :working phase for N seconds (0 < N <= 60)")
    end

    def self.register_emit(registry)
      registry.register(:"debug-emit", ->(args, ctx) {
        if args.empty?
          ctx.display.append(USAGE_EMIT, style: :error)
          next
        end
        joined = args.join(" ")
        begin
          bytes = Cclikesh::DebugCommands::EscapeInterpreter.parse(joined)
        rescue ArgumentError => e
          ctx.display.append("#{USAGE_EMIT}  (#{e.message})", style: :error)
          next
        end
        ctx.display.raw_emit(bytes)
      }, description: "emit a Ruby-escape-decoded string to stdout for sequence testing")
    end

    def self.register_color_probe(registry)
      registry.register(:"debug-color-probe", ->(_args, ctx) {
        16.times do |row|
          chunks = []
          16.times do |col|
            idx = row * 16 + col
            chunks << "\e[48;5;#{idx}m   \e[m"
          end
          ctx.display.append(chunks.join)
        end
      }, description: "dump the 256-color palette as a 16x16 grid")
    end

    def self.register_tick_counter(registry, _runtime_state = {})
      registry.register(:"debug-tick-counter", ->(_args, ctx) {
        ticks = ctx.debug_tick_count
        ctx.display.append("last 5s: #{ticks} ticks (avg #{(ticks / 5.0).round(1)}/s)", style: :dim)
      }, description: "report RelineIdlePatch tick count for the last 5 seconds")
    end

    def self.register_terminal_caps(registry)
      registry.register(:"debug-terminal-caps", ->(_args, ctx) {
        caps = ctx.debug_terminal_caps
        ctx.display.append("TERM=#{caps[:term]}",                       style: :dim)
        ctx.display.append("winsize=#{caps[:winsize].inspect}",         style: :dim)
        ctx.display.append("colors=#{caps[:colors]}",                   style: :dim)
        ctx.display.append("modify_other_keys=#{caps[:modify_other_keys]}", style: :dim)
      }, description: "report terminal capabilities (TERM / winsize / colors)")
    end

    def self.register_snapshot(registry)
      registry.register(:"debug-snapshot", ->(_args, ctx) {
        snap = ctx.debug_snapshot
        ctx.display.append("Context.state = #{snap[:context_state]}",                       style: :dim)
        ctx.display.append("Chrome.spinner_started_at = #{snap[:spinner_started_at]}",      style: :dim)
        ctx.display.append("Chrome.working_line_active? = #{snap[:working_line_active]}",   style: :dim)
      }, description: "dump live framework state")
    end

    def self.register_frame_dump(registry)
      registry.register(:"debug-frame-dump", ->(_args, ctx) {
        unless defined?(Cclikesh::DebugEndpoint) && Cclikesh::DebugEndpoint.respond_to?(:latest_frame_bytes)
          ctx.display.append("cclikesh-debug endpoint not enabled", style: :error)
          next
        end
        bytes = Cclikesh::DebugEndpoint.latest_frame_bytes
        if bytes.nil? || bytes.empty?
          ctx.display.append("no frames captured yet", style: :error)
          next
        end
        bytes.bytes.each_slice(16).with_index do |slice, row|
          offset = "%08x" % (row * 16)
          hex = slice.map { |b| "%02x" % b }.join(" ")
          ascii = slice.map { |b| (0x20..0x7e).cover?(b) ? b.chr : "." }.join
          ctx.display.append("#{offset}  #{hex.ljust(47)}  |#{ascii}|", style: :dim)
        end
      }, description: "hex-dump the latest cclikesh-debug captured frame")
    end

    # Pure-function escape interpreter for /debug-emit. Translates a
    # Ruby-style escape string into raw bytes without using eval. Only
    # the explicit escapes listed below are recognized; everything else
    # raises ArgumentError. Bytes pass through untouched.
    #
    # Recognized escapes:
    #   \e          → 0x1b (ESC)
    #   \n \r \t    → 0x0a 0x0d 0x09
    #   \\          → 0x5c (single backslash)
    #   \xNN        → byte N (exactly 2 hex digits, 0-9a-fA-F)
    #   anything else after a backslash → ArgumentError
    module EscapeInterpreter
      def self.parse(input)
        out = String.new(encoding: Encoding::ASCII_8BIT)
        i = 0
        bytes = input.b
        len = bytes.bytesize
        while i < len
          c = bytes.byteslice(i, 1)
          if c == "\\"
            raise ArgumentError, "trailing backslash" if i + 1 >= len
            n = bytes.byteslice(i + 1, 1)
            case n
            when "e" then out << "\x1b".b; i += 2
            when "n" then out << "\x0a".b; i += 2
            when "r" then out << "\x0d".b; i += 2
            when "t" then out << "\x09".b; i += 2
            when "\\" then out << "\x5c".b; i += 2
            when "x"
              hex = bytes.byteslice(i + 2, 2)
              raise ArgumentError, "incomplete \\x escape" if hex.nil? || hex.bytesize < 2
              raise ArgumentError, "non-hex digits in \\x escape: #{hex.inspect}" unless hex =~ /\A[0-9a-fA-F]{2}\z/
              out << hex.to_i(16).chr.b
              i += 4
            else
              raise ArgumentError, "unknown escape \\#{n}"
            end
          else
            out << c
            i += 1
          end
        end
        out
      end
    end
  end
end
