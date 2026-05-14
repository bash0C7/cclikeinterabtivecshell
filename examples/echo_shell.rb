# frozen_string_literal: true

require "cclikesh"

start_at = Time.now.freeze

Cclikesh.run do |shell|
  shell.header do |h|
    h.logo     "✻"
    h.title    "echo-shell"
    h.version  "v#{Cclikesh::VERSION}"
    h.subtitle "Ruby #{RUBY_VERSION} · #{Dir.pwd}"
    h.note     "echo-back demo · /q to exit"
  end

  shell.enable_debug_commands

  shell.define_style(:warn, fg: Curses::COLOR_YELLOW, bold: true)

  shell.info(:elapsed, order: 10) do |_ctx|
    sec = (Time.now - start_at).to_i
    m, s = sec.divmod(60)
    m.zero? ? "#{s}s" : "#{m}m #{s}s"
  end

  shell.status_row :clock do |row, _ctx|
    row.icon "🕒"
    row.text Time.now.strftime("%H:%M:%S")
    row.link text: "main", state: :gray
  end

  shell.spinner_label do |_ctx|
    :auto
  end

  shell.prompt_suggestion { |_ctx| "type something and watch it echo back" }
  shell.shortcuts_hint "? for shortcuts · /transcript to save log · /q to quit"

  shell.btw do |question, _ctx|
    "echo-shell heard: #{question}"
  end

  shell.on_submit do |args, ctx|
    line = args.first
    ctx.state[:phase] = :working
    ctx.display.append("you said: #{line}", style: :result)
    ctx.state[:phase] = :idle
  end

  shell.slash(:slow, description: "demo a 3-tick live slot") do |_args, ctx|
    ctx.state[:phase] = :working
    slot = ctx.display.open_live(style: :thinking)
    3.times do |i|
      sleep 0.1
      slot.update("Roosting... #{i + 1}/3")
    end
    slot.commit
    ctx.display.append("done", style: :result)
    ctx.state[:phase] = :idle
  end

  shell.slash(:dialog, description: "render a boxed dialog") do |args, ctx|
    ctx.display.dialog(args.join(" "), style: :result)
  end

  shell.slash(:warn, description: "echo bold yellow") do |args, ctx|
    ctx.display.append(args.join(" "), style: :warn)
  end

  shell.slash(:transcript, description: "show transcript hint") do |_args, ctx|
    ctx.display.append("transcript saving requires direct Main-Ractor access; not yet wired in v0.2.0", style: :dim)
  end
end
