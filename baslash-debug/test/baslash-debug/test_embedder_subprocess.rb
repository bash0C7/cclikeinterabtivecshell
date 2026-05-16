require "test/unit"
require "tmpdir"
require "fileutils"
require "drb/drb"
require "timeout"

class TestEmbedderSubprocess < Test::Unit::TestCase
  ROOT = File.expand_path("../../..", __dir__)

  def test_subprocess_embed_returns_768_dim_array
    # macOS UNIX-socket path limit is 104 bytes; default tmpdir is too long.
    dir = Dir.mktmpdir("cl-emb-", "/tmp")
    sock = File.join(dir, "e.sock")

    pid = spawn(
      { "BUNDLE_GEMFILE" => File.join(ROOT, "Gemfile") },
      "bundle", "exec", "ruby",
      File.join(ROOT, "baslash-debug/exe/baslash-debug-embedder"),
      sock,
      chdir: ROOT,
      out: File.join(dir, "out.log"), err: [:child, :out]
    )

    Timeout.timeout(120) do
      sleep 0.2 until File.exist?(sock)
    end
    sleep 0.5

    DRb.start_service
    proxy = DRbObject.new_with_uri("drbunix:#{sock}")

    vec = Timeout.timeout(120) { proxy.embed("テスト") }

    assert_kind_of Array, vec
    assert_equal 768, vec.size
    assert_kind_of Float, vec.first
  ensure
    Process.kill("TERM", pid) rescue nil
    Process.wait(pid) rescue nil
    FileUtils.rm_rf(dir) rescue nil
  end
end
