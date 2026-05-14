require "test/unit"
require "tmpdir"
require "stringio"
require "fileutils"
require "cclikesh/debug/cli/play"

class TestPlayCli < Test::Unit::TestCase
  def setup
    @dir = Dir.mktmpdir("cclikesh-play-")
    @db  = File.join(@dir, "store.sqlite")
    @spec_pass = File.join(@dir, "pass.rb")
    File.write(@spec_pass, <<~RUBY)
      session "pass-spec" do
        spawn argv: ["/bin/echo", "PASS-MARK"], cols: 40, rows: 10, env: {}
      end
      expect("contains PASS-MARK") { |c| c.contains?("PASS-MARK") }
      expect("exits zero")         { |c| c.exit_status == 0 }
    RUBY
    @spec_fail = File.join(@dir, "fail.rb")
    File.write(@spec_fail, <<~RUBY)
      session "fail-spec" do
        spawn argv: ["/bin/echo", "x"], cols: 40, rows: 10, env: {}
      end
      expect("requires NEVER") { |c| c.contains?("NEVER") }
    RUBY
    @spec_timeout = File.join(@dir, "timeout.rb")
    File.write(@spec_timeout, <<~RUBY)
      session "timeout-spec" do
        timeout 0.3
        spawn argv: ["/bin/sh", "-c", "sleep 30"], cols: 1, rows: 1, env: {}
      end
      expect("never reached") { |_c| true }
    RUBY
  end

  def teardown
    FileUtils.remove_entry(@dir)
  rescue StandardError => e
    warn "teardown cleanup failed: #{e.message}"
  end

  def run_play(spec_path)
    out = StringIO.new
    code = Cclikesh::Debug::CLI::Play.call(
      argv: [spec_path, "--db", @db],
      stdout: out
    )
    [code, out.string]
  end

  def test_all_expects_pass_returns_zero
    code, out = run_play(@spec_pass)
    assert_equal 0, code, out
    assert_match(/^PASS: contains PASS-MARK$/, out)
    assert_match(/^PASS: exits zero$/, out)
    assert_match(/^session [0-9a-f-]+ recorded \(\d+ events, \d+\.\d{2}s\)$/, out)
  end

  def test_failing_expect_returns_one
    code, out = run_play(@spec_fail)
    assert_equal 1, code, out
    assert_match(/^FAIL: requires NEVER$/, out)
  end

  def test_timeout_returns_two
    code, _out = run_play(@spec_timeout)
    assert_equal 2, code
  end

  def test_dsl_error_returns_three
    broken = File.join(@dir, "broken.rb")
    File.write(broken, "session('no-spawn') { wait 0.01 }")
    code, out = run_play(broken)
    assert_equal 3, code
    assert_match(/spec error|DslError|must call spawn/i, out)
  end

  def test_zsh_shell_slash_menu_spec_passes_under_play_cli
    repo_root = File.expand_path("../../..", __dir__)
    Dir.chdir(repo_root) do
      spec = File.join(repo_root, "cclikesh-debug/test/specs/zsh_shell_slash_menu.rb")
      out  = StringIO.new
      db   = File.join(Dir.tmpdir, "test-zsh-#{Process.pid}-#{rand(10000)}.sqlite")
      begin
        code = Cclikesh::Debug::CLI::Play.call(argv: [spec, "--db", db], stdout: out)
        assert_equal 0, code, out.string
        assert_match(/^PASS: menu lists \/pwd after typing \/$/, out.string)
        assert_match(/^PASS: menu lists \/help after typing \/$/, out.string)
        assert_match(/^PASS: session exits cleanly$/, out.string)
      ensure
        [db, "#{db}-wal", "#{db}-shm"].each { |f| File.unlink(f) if File.exist?(f) }
      end
    end
  end

  def test_pwd_output_in_body_spec_passes_under_play_cli
    repo_root = File.expand_path("../../..", __dir__)
    Dir.chdir(repo_root) do
      spec = File.join(repo_root, "cclikesh-debug/test/specs/pwd_output_in_body.rb")
      out  = StringIO.new
      db   = File.join(Dir.tmpdir, "test-pwd-#{Process.pid}-#{rand(10000)}.sqlite")
      begin
        code = Cclikesh::Debug::CLI::Play.call(argv: [spec, "--db", db], stdout: out)
        assert_equal 0, code, out.string
        assert_match(/^PASS: \/pwd output \(current working directory\) appears in the recorded stream$/, out.string)
        assert_match(/^PASS: the shortcuts hint is visible in the recorded stream$/, out.string)
        assert_match(/^PASS: session exits cleanly$/, out.string)
      ensure
        [db, "#{db}-wal", "#{db}-shm"].each { |f| File.unlink(f) if File.exist?(f) }
      end
    end
  end
end
