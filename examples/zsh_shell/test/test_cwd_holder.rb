# frozen_string_literal: true

require "test/unit"
require "tmpdir"
require_relative "../cwd_holder"

class TestCwdHolder < Test::Unit::TestCase
  def setup
    @holder = CwdHolder.new
  end

  def test_pwd_returns_current_directory
    assert_equal Dir.pwd, @holder.pwd
  end

  def test_cd_to_existing_directory
    Dir.mktmpdir do |tmp|
      @holder.cd(tmp)
      assert_equal File.realpath(tmp), File.realpath(@holder.pwd)
    end
  end

  def test_cd_nil_goes_home
    @holder.cd(nil)
    assert_equal File.realpath(ENV["HOME"]), @holder.pwd
  end

  def test_cd_empty_goes_home
    @holder.cd("")
    assert_equal File.realpath(ENV["HOME"]), @holder.pwd
  end

  def test_cd_tilde_goes_home
    @holder.cd("~")
    assert_equal File.realpath(ENV["HOME"]), @holder.pwd
  end

  def test_cd_nonexistent_raises_enoent
    before = @holder.pwd
    assert_raise(Errno::ENOENT) { @holder.cd("/no/such/path/please") }
    assert_equal before, @holder.pwd
  end

  def test_cd_relative_resolves_from_current_cwd
    Dir.mktmpdir do |tmp|
      sub = File.join(tmp, "sub")
      Dir.mkdir(sub)
      @holder.cd(tmp)
      @holder.cd("sub")
      assert_equal File.realpath(sub), File.realpath(@holder.pwd)
    end
  end

  def test_reset_restores_initial
    initial = @holder.pwd
    Dir.mktmpdir do |tmp|
      @holder.cd(tmp)
      @holder.reset
      assert_equal initial, @holder.pwd
    end
  end
end
