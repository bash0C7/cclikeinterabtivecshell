require_relative "test_helper"
require "cclikesh/shareable_ref"

class TestShareableRef < Test::Unit::TestCase
  class Counter
    def initialize; @n = 0; end
    def add(x); @n += x; end
    def value; @n; end
  end

  def test_call_routes_method_to_owned_object_in_ractor
    ref = Cclikesh::ShareableRef.spawn(:counter) { Counter.new }
    ref.call(:add, 5)
    ref.call(:add, 7)
    assert_equal 12, ref.call(:value)
  ensure
    ref&.stop
  end

  def test_two_refs_have_isolated_state
    a = Cclikesh::ShareableRef.spawn(:a) { Counter.new }
    b = Cclikesh::ShareableRef.spawn(:b) { Counter.new }
    a.call(:add, 1); a.call(:add, 1)
    b.call(:add, 100)
    assert_equal 2,   a.call(:value)
    assert_equal 100, b.call(:value)
  ensure
    a&.stop; b&.stop
  end

  def test_stop_terminates_ractor
    ref = Cclikesh::ShareableRef.spawn(:c) { Counter.new }
    ref.stop
    sleep 0.05  # Let Ractor termination propagate
    assert_raise(Ractor::ClosedError, Ractor::Error) { ref.call(:value) }
  end

  def test_name_accessible
    ref = Cclikesh::ShareableRef.spawn(:my_name) { Counter.new }
    assert_equal :my_name, ref.name
  ensure
    ref&.stop
  end
end
