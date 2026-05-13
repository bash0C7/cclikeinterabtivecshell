# frozen_string_literal: true

require "test/unit"
require_relative "../zsh_runner"

class TestZshRunnerParse < Test::Unit::TestCase
  def test_empty_line
    assert_equal({kind: :empty}, ZshRunner.parse(""))
    assert_equal({kind: :empty}, ZshRunner.parse("   "))
  end

  def test_plain_command
    assert_equal({kind: :run, line: "ls -la"}, ZshRunner.parse("ls -la"))
  end

  def test_cd_with_path
    assert_equal({kind: :cd, path: "/tmp"}, ZshRunner.parse("cd /tmp"))
  end

  def test_cd_no_args_goes_home
    assert_equal({kind: :cd, path: nil}, ZshRunner.parse("cd"))
  end

  def test_cd_tilde
    assert_equal({kind: :cd, path: "~"}, ZshRunner.parse("cd ~"))
  end

  def test_cd_dash_is_error
    assert_equal :error, ZshRunner.parse("cd -")[:kind]
  end

  def test_cd_too_many_args
    assert_equal :error, ZshRunner.parse("cd a b")[:kind]
  end

  def test_export_assignment
    assert_equal({kind: :export, name: "FOO", value: "bar"}, ZshRunner.parse("export FOO=bar"))
  end

  def test_export_quoted_value
    assert_equal({kind: :export, name: "FOO", value: "bar baz"}, ZshRunner.parse('export FOO="bar baz"'))
  end

  def test_export_no_args
    assert_equal :error, ZshRunner.parse("export")[:kind]
  end

  def test_export_no_value
    assert_equal :error, ZshRunner.parse("export FOO")[:kind]
  end

  def test_export_multiple_assignments
    assert_equal :error, ZshRunner.parse("export FOO=bar BAZ=qux")[:kind]
  end

  def test_unset
    assert_equal({kind: :unset, name: "FOO"}, ZshRunner.parse("unset FOO"))
  end

  def test_unset_no_args
    assert_equal :error, ZshRunner.parse("unset")[:kind]
  end

  def test_unbalanced_quotes_falls_back_to_run
    result = ZshRunner.parse("echo 'unbalanced")
    assert_equal :run, result[:kind]
  end

  def test_result_is_frozen
    assert_predicate ZshRunner.parse("ls"), :frozen?
  end
end
