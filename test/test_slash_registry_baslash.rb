# frozen_string_literal: true

require_relative "test_helper"
require "baslash/slash_registry"

class TestSlashRegistryBaslash < Test::Unit::TestCase
  def test_register_and_lookup
    reg = Baslash::SlashRegistry.new
    body = proc { |args, ctx| args.size }
    reg.register(:echo, body, description: "echo test")
    entry = reg.lookup(:echo)
    refute_nil entry
    assert_equal "echo test", entry[:description]
    assert_kind_of Proc, entry[:body]
  end

  def test_register_preserves_closure_variables
    registry = Baslash::SlashRegistry.new
    external = "captured value"
    registry.register(:closure_test, proc { |_args, _ctx| external })
    entry = registry.lookup("closure_test")
    result = entry[:body].call([], nil)
    assert_equal "captured value", result
  end

  def test_lookup_unknown_returns_nil
    reg = Baslash::SlashRegistry.new
    assert_nil reg.lookup(:nope)
  end

  def test_lookup_nil_returns_nil
    reg = Baslash::SlashRegistry.new
    reg.register(:echo, proc {}, description: "echo")
    assert_nil reg.lookup(nil)
  end

  def test_lookup_empty_string_returns_nil
    reg = Baslash::SlashRegistry.new
    reg.register(:echo, proc {}, description: "echo")
    assert_nil reg.lookup("")
  end

  def test_each_iterates_in_insertion_order
    reg = Baslash::SlashRegistry.new
    reg.register(:a, proc {}, description: "a")
    reg.register(:b, proc {}, description: "b")
    reg.register(:c, proc {}, description: "c")
    assert_equal [:a, :b, :c], reg.each.map { |name, _| name }
  end

  def test_all_returns_frozen_snapshot
    reg = Baslash::SlashRegistry.new
    reg.register(:x, proc {}, description: "x")
    snapshot = reg.all
    assert snapshot.frozen?
  end

  def test_register_stores_hotkey
    reg = Baslash::SlashRegistry.new
    reg.register(:reset, proc {}, description: "reset", hotkey: "C-g")
    entry = reg.lookup(:reset)
    assert_equal "C-g", entry[:hotkey]
  end

  def test_register_defaults_hotkey_to_nil
    reg = Baslash::SlashRegistry.new
    reg.register(:reset, proc {}, description: "reset")
    assert_nil reg.lookup(:reset)[:hotkey]
  end

  def test_slash_menu_items_include_hotkey
    reg = Baslash::SlashRegistry.new
    reg.register(:reset, proc {}, description: "reset", hotkey: "C-g")
    reg.register(:plain, proc {}, description: "plain")
    items = reg.slash_menu_items_starting_with("")
    reset = items.find { |i| i[:name] == "/reset" }
    plain = items.find { |i| i[:name] == "/plain" }
    assert_equal "C-g", reset[:hotkey]
    assert_nil   plain[:hotkey]
  end

  def test_update_hotkey_for_existing_entry
    reg = Baslash::SlashRegistry.new
    body = proc {}
    reg.register(:exit, body, description: "exit")
    reg.update_hotkey(:exit, "C-d")
    entry = reg.lookup(:exit)
    assert_equal "C-d", entry[:hotkey]
    assert_same body, entry[:body]
    assert_equal "exit", entry[:description]
  end

  def test_update_hotkey_on_unknown_name_raises
    reg = Baslash::SlashRegistry.new
    assert_raise(KeyError) { reg.update_hotkey(:nope, "C-g") }
  end
end
