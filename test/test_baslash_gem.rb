require "test/unit"

class TestBaslashGem < Test::Unit::TestCase
  def test_baslash_module_loads
    require "baslash"
    assert defined?(Baslash)
    assert defined?(Baslash::VERSION)
    assert_match(/\A\d+\.\d+\.\d+\z/, Baslash::VERSION)
  end

  def test_baslash_run_signature
    require "baslash"
    assert_respond_to Baslash, :run
  end
end
