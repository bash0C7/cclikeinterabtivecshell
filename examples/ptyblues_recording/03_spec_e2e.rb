# frozen_string_literal: true
#
# Standalone E2E sample for examples/echo_shell.rb via ptyblues-inspect SpecDSL.
# Run from the baslash repo root:
#   bundle exec ruby examples/ptyblues_recording/03_spec_e2e.rb
#
# This script does NOT need the ptyblues hub. SpecDSL.evaluate spawns the PTY
# directly, records into a tmp sqlite DB, and evaluates the expect blocks.

require "ptyblues/inspect"
require "tmpdir"

SPEC_SOURCE = <<~SPEC
  session "echo_shell smoke" do
    timeout 10
    spawn argv: ["bundle", "exec", "ruby", "examples/echo_shell.rb"],
          cols: 80, rows: 24
    wait 0.5
    send "/slow\\r"
    wait 1.5
    send "\\u0004"
  end

  expect "/slow produced 'done' marker" do |captured|
    captured.contains?("done")
  end

  expect "process exited (any status)" do |captured|
    !captured.exit_status.nil?
  end
SPEC

exit_code = Dir.mktmpdir("baslash-e2e-") do |dir|
  db_path = File.join(dir, "spec.sqlite")
  result  = Ptyblues::Inspect::SpecDSL.evaluate(
    SPEC_SOURCE,
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
  puts
  puts "#{pass_count}/#{results.size} passed"
  results.all? { |r| r[:pass] } ? 0 : 1
end

exit exit_code
