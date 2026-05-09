# frozen_string_literal: true

require_relative "test_helper"
require "cclikesh/endpoint"

class TestEndpoint < Test::Unit::TestCase
  def test_uri_is_drb_unix
    uri = Cclikesh::Endpoint.uri(:handlers)
    assert_match %r{\Adrbunix://}, uri
  end

  def test_uri_includes_role_name
    uri = Cclikesh::Endpoint.uri(:handlers)
    assert_match(/handlers/, uri)
  end

  def test_uri_is_unique_per_call_for_different_roles
    h = Cclikesh::Endpoint.uri(:handlers)
    c = Cclikesh::Endpoint.uri(:context)
    assert_not_equal h, c
  end

  def test_socket_path_in_tmpdir
    uri = Cclikesh::Endpoint.uri(:handlers)
    path = uri.sub(%r{\Adrbunix://}, "")
    assert_match(/\A#{Regexp.escape(Dir.tmpdir)}/, path)
  end
end
