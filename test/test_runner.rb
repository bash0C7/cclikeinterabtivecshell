# frozen_string_literal: true

require_relative "test_helper"
require "cclikesh"

class TestRunner < Test::Unit::TestCase
  def setup
    Dir.mkdir("tmp") unless Dir.exist?("tmp")
    pid_rand = "#{Process.pid}_#{rand(99999)}"
    @input_path = "tmp/test_runner_in_#{pid_rand}.txt"
    @output_path = "tmp/test_runner_out_#{pid_rand}.txt"
    File.write(@output_path, "")
  end

  def teardown
    [@input_path, @output_path].each do |p|
      File.unlink(p) if p && File.exist?(p)
    end
  end

  def test_echo_shell_end_to_end
    File.write(@input_path, "hello\n/quit\n")
    Cclikesh.run(input_path: @input_path, output_path: @output_path) do |shell|
      shell.on_submit { |line, ctx| ctx.display.append("you said: #{line}") }
      shell.slash(:quit) { |args, ctx| ctx.quit }
    end
    assert_equal "you said: hello\n", File.read(@output_path)
  end

  def test_unknown_slash_renders_error
    File.write(@input_path, "/nope\n/quit\n")
    Cclikesh.run(input_path: @input_path, output_path: @output_path) do |shell|
      shell.slash(:quit) { |args, ctx| ctx.quit }
    end
    assert_match(/nope.*not registered/, File.read(@output_path))
  end

  def test_eof_terminates_loop
    File.write(@input_path, "alpha\n")
    Cclikesh.run(input_path: @input_path, output_path: @output_path) do |shell|
      shell.on_submit { |line, ctx| ctx.display.append(line) }
    end
    assert_equal "alpha\n", File.read(@output_path)
  end
end
