# frozen_string_literal: true

require "rake/testtask"

Rake::TestTask.new(:test) do |t|
  t.libs << "test"
  t.libs << "lib"
  t.test_files = FileList["test/test_*.rb"]
  t.warning = false
end

task default: :test

# Debug recording session via the local baslash-debug gem. Macos's 104-byte
# Unix-socket-path limit forces us to use a short BASLASH_DEBUG_DIR; rooting
# everything under /tmp/cclk keeps the control socket path well under the cap.
namespace :debug do
  DEBUG_DIR = "/tmp/cclk"

  desc "Start a recorded session of an example (default: zsh_shell). RAKE_DEBUG_TARGET=<path> to override."
  task :start do
    target = ENV["RAKE_DEBUG_TARGET"] || "examples/zsh_shell/zsh_shell.rb"
    cadence = ENV["RAKE_DEBUG_CADENCE_MS"] || "200"
    note    = ENV["RAKE_DEBUG_NOTE"]
    mkdir_p DEBUG_DIR
    args = ["start", File.expand_path(target), "--cadence-ms", cadence, "--no-vector"]
    args.push("--note", note) if note
    sh({ "BASLASH_DEBUG_DIR" => DEBUG_DIR }, "bundle", "exec", "exe/baslash-debug", *args,
       chdir: "baslash-debug")
  end

  desc "List recorded sessions."
  task :list do
    sh({ "BASLASH_DEBUG_DIR" => DEBUG_DIR }, "bundle", "exec", "exe/baslash-debug", "list",
       chdir: "baslash-debug")
  end

  desc "Send input to a session. SESSION=<short-uuid> TEXT='...' (supports \\r, \\t, \\e, \\n)."
  task :input do
    session = ENV["SESSION"] or abort("SESSION=<short-uuid> required")
    text    = ENV["TEXT"]    or abort("TEXT='...' required")
    sh({ "BASLASH_DEBUG_DIR" => DEBUG_DIR }, "bundle", "exec", "exe/baslash-debug",
       "input", session, text, chdir: "baslash-debug")
  end

  desc "Trigger an on-demand capture for SESSION=<short-uuid>."
  task :capture do
    session = ENV["SESSION"] or abort("SESSION=<short-uuid> required")
    sh({ "BASLASH_DEBUG_DIR" => DEBUG_DIR }, "bundle", "exec", "exe/baslash-debug",
       "capture", session, chdir: "baslash-debug")
  end

  desc "Stop a recording session. SESSION=<short-uuid>."
  task :stop do
    session = ENV["SESSION"] or abort("SESSION=<short-uuid> required")
    sh({ "BASLASH_DEBUG_DIR" => DEBUG_DIR }, "bundle", "exec", "exe/baslash-debug",
       "stop", session, chdir: "baslash-debug")
  end

  desc "List frames in a session. SESSION=<short-uuid>."
  task :frames do
    session = ENV["SESSION"] or abort("SESSION=<short-uuid> required")
    sh({ "BASLASH_DEBUG_DIR" => DEBUG_DIR }, "bundle", "exec", "exe/baslash-debug",
       "frames", session, chdir: "baslash-debug")
  end

  desc "Dump a frame's raw terminal bytes. SESSION=<short-uuid> FRAME=<id>."
  task :grid do
    session = ENV["SESSION"] or abort("SESSION=<short-uuid> required")
    frame   = ENV["FRAME"]   or abort("FRAME=<id> required")
    sh({ "BASLASH_DEBUG_DIR" => DEBUG_DIR }, "bundle", "exec", "exe/baslash-debug",
       "grid", session, "--frame", frame, chdir: "baslash-debug")
  end
end

desc "Start a recorded debug session of examples/zsh_shell/zsh_shell.rb (alias for debug:start)."
task debug: "debug:start"
