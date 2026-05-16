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
    assert Ractor.shareable?(entry[:body])
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
end
