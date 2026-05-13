# frozen_string_literal: true

require "rake/testtask"

Rake::TestTask.new(:test) do |t|
  t.libs << "test"
  t.libs << "lib"
  t.test_files = FileList["test/test_*.rb"]
  t.warning = false
end

task default: :test

# Debug recording session via the local cclikesh-debug gem. Macos's 104-byte
# Unix-socket-path limit forces us to use a short CCLIKESH_DEBUG_DIR; rooting
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
    sh({ "CCLIKESH_DEBUG_DIR" => DEBUG_DIR }, "bundle", "exec", "exe/cclikesh-debug", *args,
       chdir: "cclikesh-debug")
  end

  desc "List recorded sessions."
  task :list do
    sh({ "CCLIKESH_DEBUG_DIR" => DEBUG_DIR }, "bundle", "exec", "exe/cclikesh-debug", "list",
       chdir: "cclikesh-debug")
  end

  desc "Send input to a session. SESSION=<short-uuid> TEXT='...' (supports \\r, \\t, \\e, \\n)."
  task :input do
    session = ENV["SESSION"] or abort("SESSION=<short-uuid> required")
    text    = ENV["TEXT"]    or abort("TEXT='...' required")
    sh({ "CCLIKESH_DEBUG_DIR" => DEBUG_DIR }, "bundle", "exec", "exe/cclikesh-debug",
       "input", session, text, chdir: "cclikesh-debug")
  end

  desc "Trigger an on-demand capture for SESSION=<short-uuid>."
  task :capture do
    session = ENV["SESSION"] or abort("SESSION=<short-uuid> required")
    sh({ "CCLIKESH_DEBUG_DIR" => DEBUG_DIR }, "bundle", "exec", "exe/cclikesh-debug",
       "capture", session, chdir: "cclikesh-debug")
  end

  desc "Stop a recording session. SESSION=<short-uuid>."
  task :stop do
    session = ENV["SESSION"] or abort("SESSION=<short-uuid> required")
    sh({ "CCLIKESH_DEBUG_DIR" => DEBUG_DIR }, "bundle", "exec", "exe/cclikesh-debug",
       "stop", session, chdir: "cclikesh-debug")
  end

  desc "List frames in a session. SESSION=<short-uuid>."
  task :frames do
    session = ENV["SESSION"] or abort("SESSION=<short-uuid> required")
    sh({ "CCLIKESH_DEBUG_DIR" => DEBUG_DIR }, "bundle", "exec", "exe/cclikesh-debug",
       "frames", session, chdir: "cclikesh-debug")
  end

  desc "Dump a frame's raw terminal bytes. SESSION=<short-uuid> FRAME=<id>."
  task :grid do
    session = ENV["SESSION"] or abort("SESSION=<short-uuid> required")
    frame   = ENV["FRAME"]   or abort("FRAME=<id> required")
    sh({ "CCLIKESH_DEBUG_DIR" => DEBUG_DIR }, "bundle", "exec", "exe/cclikesh-debug",
       "grid", session, "--frame", frame, chdir: "cclikesh-debug")
  end
end

desc "Start a recorded debug session of examples/zsh_shell/zsh_shell.rb (alias for debug:start)."
task debug: "debug:start"
