require "test/unit"
require "stringio"
require "open3"

class TestSmoke < Test::Unit::TestCase
  def test_echo_shell_does_not_enter_alt_screen
    out, _err, _status = Open3.capture3(
      { "TERM" => "xterm-256color" },
      "bundle", "exec", "ruby", "examples/echo_shell.rb",
      stdin_data: "/q\n",
      chdir: File.expand_path("..", __dir__)
    )
    refute out.include?("\e[?1049h"),
           "echo_shell must not emit smcup (\\e[?1049h); captured stdout: #{out.inspect[0, 200]}"
    assert out.bytesize > 0, "expected some stdout from echo_shell"
  end
end
