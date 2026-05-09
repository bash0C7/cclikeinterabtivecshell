# frozen_string_literal: true

require_relative "test_helper"

class TestSmoke < Test::Unit::TestCase
  def test_version_is_defined
    assert_match(/\A\d+\.\d+\.\d+\z/, Cclikesh::VERSION)
  end

  def test_module_loadable
    assert_equal Module, Cclikesh.class
  end
end
