# frozen_string_literal: true

module Baslash
  class SlashRegistry
    def initialize
      @entries = {}
    end

    def register(name, body, description: nil)
      shareable_body = Ractor.shareable_proc(&body)
      @entries[name.to_sym] = {
        body:        shareable_body,
        description: description.to_s.freeze
      }.freeze
    end

    def lookup(name)
      @entries[name.to_sym]
    end

    def each(&block)
      @entries.each(&block)
    end

    def all
      @entries.dup.freeze
    end

    # Items consumed by the slash-menu dialog. Returns every entry whose
    # name (without the leading slash) starts with `prefix`. The dialog
    # uses :name (with the slash) and :description verbatim, so we
    # synthesize the displayed name here rather than letting the dialog
    # piece it together. Result order matches insertion order so the
    # default + plugin + user-extension layering is preserved on screen.
    def slash_menu_items_starting_with(prefix)
      prefix_str = prefix.to_s
      result = []
      @entries.each do |name, entry|
        name_str = name.to_s
        next unless name_str.start_with?(prefix_str)
        result << { name: "/#{name_str}", description: entry[:description] }
      end
      result
    end
  end
end
