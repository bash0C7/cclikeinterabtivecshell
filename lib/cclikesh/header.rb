# frozen_string_literal: true

require_relative "layout"

module Cclikesh
  module Header
    class Configurator
      ATTRS = %i[logo title version subtitle note].freeze
      attr_accessor(*ATTRS)

      ATTRS.each do |name|
        define_method(name) do |value = nil|
          if value.nil?
            instance_variable_get("@#{name}")
          else
            instance_variable_set("@#{name}", value)
          end
        end
      end

      def lines
        out = []
        title_line = build_title_line
        out << title_line if title_line
        out << "   #{subtitle}" if subtitle && !subtitle.empty?
        out << "   #{note}"     if note     && !note.empty?
        out
      end

      def height
        ls = lines
        ls.empty? ? 0 : ls.size + 3
      end

      private

      def build_title_line
        has_logo  = logo  && !logo.empty?
        has_title = title && !title.empty?
        return nil unless has_logo || has_title

        title_part = if has_title && version && !version.empty?
                       "#{title} #{version}"
                     elsif has_title
                       title
                     end

        if has_logo && title_part
          "#{logo}  #{title_part}"
        elsif has_logo
          logo
        else
          title_part
        end
      end
    end

    def self.paint(io, content_lines, cols: nil)
      return if content_lines.nil? || content_lines.empty?
      rendered = cols ? box(content_lines, cols) : content_lines
      rendered.each_with_index do |line, idx|
        Layout.position(io, idx + 1, 1)
        Layout.clear_line(io)
        io.write(line) if line
      end
      Layout.position(io, rendered.size + 1, 1)
      Layout.clear_line(io)
    end

    def self.box(content_lines, cols)
      return [] if content_lines.nil? || content_lines.empty?
      inner_w = [cols - 4, 1].max
      bar_w   = [cols - 2, 1].max
      top    = "╭" + ("─" * bar_w) + "╮"
      bottom = "╰" + ("─" * bar_w) + "╯"
      body = content_lines.map do |line|
        visible = line.to_s.length
        pad = [inner_w - visible, 0].max
        "│ #{line}#{" " * pad} │"
      end
      [top, *body, bottom]
    end
  end
end
