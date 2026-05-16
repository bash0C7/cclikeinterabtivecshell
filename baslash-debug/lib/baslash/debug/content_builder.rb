module Baslash
  module Debug
    module ContentBuilder
      def self.build(state)
        parts = []
        header = get(state, :header) || {}
        parts << get(header, :note)

        Array(get(state, :info_bar)).each { |i| parts << get(i, :text) }

        Array(get(state, :status_rows)).each do |r|
          Array(get(r, :segments)).each { |s| parts << get(s, :text) }
        end

        input = get(state, :input) || {}
        parts << get(input, :buffer)

        live = get(state, :live_slot) || {}
        parts << get(live, :text) if get(live, :active)

        popup = get(state, :popup) || {}
        if get(popup, :active)
          kind = get(popup, :kind)
          n    = get(popup, :candidates_count) || 0
          parts << "popup:#{kind}:#{n}"
        end

        parts.compact.reject { |p| p.respond_to?(:empty?) && p.empty? }.join("\n")
      end

      def self.get(hash, key)
        return nil unless hash.is_a?(Hash)
        hash[key.to_sym] || hash[key.to_s]
      end
    end
  end
end
