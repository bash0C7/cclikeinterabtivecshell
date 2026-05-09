# frozen_string_literal: true

require "cclikesh"

start_at = Time.now

Cclikesh.run do |shell|
  shell.header do |h|
    h.logo     "✻"
    h.title    "echo-shell"
    h.version  "v#{Cclikesh::VERSION}"
    h.subtitle "Ruby #{RUBY_VERSION} · #{Dir.pwd}"
    h.note     "echo-back demo · /q to exit"
  end

  shell.define_style(:warn, fg: :yellow, bold: true)

  shell.info(:elapsed, order: 10) do |_ctx|
    sec = (Time.now - start_at).to_i
    m, s = sec.divmod(60)
    m.zero? ? "#{s}s" : "#{m}m #{s}s"
  end

  shell.info(:phase, order: 20) do |ctx|
    ctx.state[:phase].to_s if ctx.state[:phase]
  end

  shell.status_row :clock do |row, _ctx|
    row.icon "🕒"
    row.text Time.now.strftime("%H:%M:%S")
    row.link text: "main", state: :gray
  end

  shell.spinner_label do |ctx|
    case ctx.state[:phase]
    when :working then :auto
    when :awaiting then "Awaiting"
    end
  end

  shell.prompt_suggestion { |_ctx| "type something and watch it echo back" }

  shell.shortcuts_hint "? for shortcuts · /transcript to save log · /q to quit"

  shell.btw do |question, _ctx|
    "echo-shell heard: #{question}"
  end

  shell.on_submit do |line, ctx|
    ctx.state[:phase] = :working
    ctx.display.append("you said: #{line}", style: :result)
    ctx.state[:phase] = nil
  end

  shell.slash(:slow, description: "demo a 3-tick live slot") do |_args, ctx|
    ctx.state[:phase] = :working
    ctx.display.open_live(style: :thinking) do |slot|
      3.times do |i|
        sleep 0.1
        slot.update("Roosting... #{i + 1}/3")
      end
    end
    ctx.display.append("done", style: :result)
    ctx.state[:phase] = nil
  end

  shell.slash(:dialog, description: "render a boxed dialog") do |args, ctx|
    ctx.dialog.show(args.join(" "), style: :result)
  end

  shell.slash(:warn, description: "echo bold yellow") do |args, ctx|
    ctx.display.append(args.join(" "), style: :warn)
  end

  shell.slash(:quit, description: "exit") { |_args, ctx| ctx.quit }
  shell.slash(:q,    description: "exit") { |_args, ctx| ctx.quit }
end
