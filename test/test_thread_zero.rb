require "test/unit"

class TestThreadZero < Test::Unit::TestCase
  ROOT = File.expand_path("..", __dir__)

  def test_no_thread_new_in_application_code
    paths = [
      File.join(ROOT, "lib"),
      File.join(ROOT, "examples")
    ]
    hits = []
    paths.each do |p|
      Dir.glob(File.join(p, "**/*.rb"), File::FNM_DOTMATCH).each do |f|
        next if File.directory?(f)
        File.read(f).each_line.with_index(1) do |line, lineno|
          stripped = line.sub(/#.*$/, "")
          if stripped =~ /Thread\.(?:new|fork|start)\b/
            hits << "#{f}:#{lineno}: #{line.strip}"
          end
        end
      end
    end
    assert hits.empty?, "Thread禁止 violation:\n#{hits.join("\n")}"
  end
end
