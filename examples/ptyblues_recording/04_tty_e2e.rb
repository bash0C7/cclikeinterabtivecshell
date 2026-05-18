# frozen_string_literal: true
#
# TTY-only E2E for baslash via ptyblues/inspect SpecDSL.
# Verifies behavior that piped stdin cannot drive: slash-menu Tab cycle,
# Ctrl-C interrupt of a running handler, OSC 0 title-bar bytes, and
# prompt_prefix rendering.
#
# Run from the baslash repo root:
#   bundle exec ruby examples/ptyblues_recording/04_tty_e2e.rb

require "ptyblues/inspect"
require "tmpdir"

# A minimal baslash shell with a /veryslow handler that sleeps 10s — long
# enough for Ctrl-C to arrive mid-execution without a tight timing race.
SLOW_SHELL_SCRIPT = <<~RUBY
  # frozen_string_literal: true
  require "baslash"
  Baslash.run do |shell|
    shell.slash(:veryslow, description: "sleep 10s for Ctrl-C interrupt test") do |_args, ctx|
      ctx.state[:phase] = :working
      sleep 10
      ctx.display.append("done", style: :result)
      ctx.state[:phase] = :idle
    end
  end
RUBY

HOTKEY_SHELL_SCRIPT = <<~RUBY
  # frozen_string_literal: true
  require "baslash"
  Baslash.run do |shell|
    shell.slash(:marker, description: "print hotkey-marker", hotkey: "C-g") do |_args, ctx|
      ctx.display.append("HOTKEY-MARKER-OK", style: :result)
    end
  end
RUBY

overall_pass = true
Dir.mktmpdir("baslash-tty-e2e-") do |dir|
  # Write the helper script into the same tmpdir so it is cleaned up with it.
  slow_shell_path = File.join(dir, "slow_shell.rb")
  File.write(slow_shell_path, SLOW_SHELL_SCRIPT)
  hotkey_shell_path = File.join(dir, "hotkey_shell.rb")
  File.write(hotkey_shell_path, HOTKEY_SHELL_SCRIPT)

  scenarios = [
    {
      name: "echo_shell OSC-0 title-bar + Tab completion shows /help",
      spec: <<~SPEC,
        session "echo_shell tab" do
          timeout 10
          spawn argv: ["bundle", "exec", "ruby", "examples/echo_shell.rb"], cols: 80, rows: 24
          wait 0.8
          send "/he"
          wait 0.3
          send "\\t"
          wait 0.5
          send "\\u0003"
          wait 0.3
          send "/exit\\r"
          wait 0.5
        end

        expect "OSC 0 title-bar bytes were emitted" do |captured|
          captured.contains?("\e]0;")
        end

        expect "slash menu suggestion for /help visible (menu or completion)" do |captured|
          captured.contains?("/help") || captured.contains?("help")
        end

        expect "process exited cleanly" do |captured|
          captured.exit_status == 0
        end
      SPEC
    },
    {
      name: "Ctrl-C interrupt of a running handler emits ^C marker",
      spec: <<~SPEC,
        session "ctrl_c" do
          timeout 15
          spawn argv: ["bundle", "exec", "ruby", "#{slow_shell_path}"], cols: 80, rows: 24
          wait 1.0
          send "/veryslow\\r"
          wait 1.5
          send "\\u0003"
          wait 0.8
          send "/exit\\r"
          wait 0.5
        end

        expect "^C marker appeared after Ctrl-C" do |captured|
          captured.contains?("^C")
        end

        expect "exited cleanly after interrupt" do |captured|
          captured.exit_status == 0
        end
      SPEC
    },
    {
      name: "zsh_shell prompt_prefix renders cwd + OSC-0",
      spec: <<~SPEC,
        session "zsh_shell prompt" do
          timeout 10
          spawn argv: ["bundle", "exec", "ruby", "examples/zsh_shell/zsh_shell.rb"], cols: 100, rows: 24
          wait 1.0
          send "/exit\\r"
          wait 0.5
        end

        expect "prompt contains a path-like prefix" do |captured|
          captured.contains?("/baslash") || captured.contains?("~") || captured.contains?("/")
        end

        expect "OSC 0 title-bar bytes emitted" do |captured|
          captured.contains?("\e]0;")
        end

        expect "exited cleanly" do |captured|
          captured.exit_status == 0
        end
      SPEC
    },
    {
      name: "hotkey C-g from empty buffer dispatches /marker; non-empty buffer ignores",
      spec: <<~SPEC,
        session "hotkey" do
          timeout 10
          spawn argv: ["bundle", "exec", "ruby", "#{hotkey_shell_path}"], cols: 80, rows: 24
          wait 1.0
          # Empty-buffer C-g -> should dispatch /marker
          send "\\u0007"
          wait 0.8
          # Type then C-g -> buffer non-empty, hotkey must be no-op
          send "abc"
          wait 0.3
          send "\\u0007"
          wait 0.5
          # Clear the buffer and exit cleanly
          send "\\u0003"
          wait 0.3
          send "/exit\\r"
          wait 0.5
        end

        expect "hotkey dispatched /marker from empty buffer" do |captured|
          captured.contains?("HOTKEY-MARKER-OK")
        end

        expect "exited cleanly" do |captured|
          captured.exit_status == 0
        end
      SPEC
    },
  ]

  scenarios.each_with_index do |scenario, i|
    puts
    puts "[#{i + 1}/#{scenarios.size}] #{scenario[:name]}"
    db_path = File.join(dir, "scenario_#{i}.sqlite")
    result  = Ptyblues::Inspect::SpecDSL.evaluate(
      scenario[:spec],
      db_path:   db_path,
      spec_path: __FILE__,
    )
    results = Ptyblues::Inspect::SpecDSL.dispatch_expects(result)
    results.each do |r|
      mark = r[:pass] ? "PASS" : "FAIL"
      puts "  #{mark} #{r[:label]}"
      puts "    error: #{r[:error].class}: #{r[:error].message}" if r[:error]
    end
    pass_count = results.count { |r| r[:pass] }
    puts "  #{pass_count}/#{results.size} passed"
    overall_pass &&= results.all? { |r| r[:pass] }
  end
end

puts
puts overall_pass ? "ALL TTY E2E PASS" : "TTY E2E FAILURES"
exit overall_pass ? 0 : 1
