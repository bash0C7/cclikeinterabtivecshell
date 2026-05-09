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
        ls.empty? ? 0 : ls.size + 1
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

    def self.paint(io, lines)
      return if lines.nil? || lines.empty?
      lines.each_with_index do |line, idx|
        Layout.position(io, idx + 1, 1)
        Layout.clear_line(io)
        io.write(line)
      end
      Layout.position(io, lines.size + 1, 1)
      Layout.clear_line(io)
    end
  end
end
