# frozen_string_literal: true

require_relative "style"

module Cclikesh
  module InfoBar
    def self.compose(spinner_frame:, spinner_label:, segments:)
      label_part = build_label_part(spinner_frame, spinner_label)
      seg_part   = build_segments_part(segments)

      parts = [label_part, seg_part].reject { |p| p.nil? || p.empty? }
      parts.join("  ")
    end

    def self.build_label_part(frame, label)
      return "" if label.nil? || label.empty?
      label_styled = Style.wrap(label, :thinking)
      frame.nil? || frame.empty? ? label_styled : "#{Style.wrap(frame, :thinking)} #{label_styled}"
    end

    def self.build_segments_part(segments)
      return "" if segments.nil? || segments.empty?
      joined = segments.join(" · ")
      "(#{Style.wrap(joined, :dim)})"
    end
  end
end
