# frozen_string_literal: true

require "cclikesh"
require_relative "cwd_holder"
require_relative "env_holder"
require_relative "zsh_runner"

start_at = Time.now.freeze

Cclikesh.run do |shell|
  shell.shareable_ref(:cwd) { CwdHolder.new }
  shell.shareable_ref(:env) { EnvHolder.new }

  shell.define_style(:ok, fg: Curses::COLOR_GREEN, bold: true)
  shell.define_style(:ng, fg: Curses::COLOR_RED,   bold: true)

  shell.header do |h|
    h.logo     "✻"
    h.title    "zsh-shell"
    h.version  "v#{Cclikesh::VERSION}"
    h.subtitle "Ruby #{RUBY_VERSION}"
    h.note     "cd/export intercepted · /q to quit"
  end

  shell.info(:elapsed, order: 10) do |_ctx|
    sec = (Time.now - start_at).to_i
    m, s = sec.divmod(60)
    m.zero? ? "#{s}s" : "#{m}m #{s}s"
  end

  shell.status_row(:cwd) do |row, ctx|
    cwd = ctx.shareable(:cwd).call(:pwd)
    home = ENV["HOME"] || ""
    display = !home.empty? && cwd.start_with?(home) ? cwd.sub(home, "~") : cwd
    row.icon "📁"
    row.text display
  end

  shell.status_row(:env) do |row, ctx|
    size = ctx.shareable(:env).call(:size)
    row.icon "🌱"
    row.text "#{size} vars"
  end

  shell.status_row(:last) do |row, ctx|
    code = ctx.state[:last_status]
    elapsed = ctx.state[:last_elapsed]
    if code.nil?
      row.icon "⏳"
      row.text "ready"
    elsif code.zero?
      row.icon "✓"
      row.text "exit 0 · #{elapsed&.round(2)}s"
    else
      row.icon "✗"
      row.text "exit #{code} · #{elapsed&.round(2)}s"
    end
  end

  shell.spinner_label { |_| :auto }
  shell.prompt_suggestion { |_| "ls / git status / find . -name '*.rb' …" }
  shell.shortcuts_hint "/q quit · /pwd · /env · /reset"

  shell.btw do |question, _ctx|
    "(zsh-shell heard: #{question})"
  end

  shell.slash(:pwd, description: "show cwd") do |_args, ctx|
    ctx.display.append(ctx.shareable(:cwd).call(:pwd), style: :result)
  end

  shell.slash(:env, description: "list environment") do |_args, ctx|
    snapshot = ctx.shareable(:env).call(:snapshot)
    snapshot.sort.each do |k, v|
      value = v.length > 80 ? "#{v[0, 77]}..." : v
      ctx.display.append("#{k}=#{value}", style: :dim)
    end
  end

  shell.slash(:reset, description: "reset cwd and env") do |_args, ctx|
    ctx.shareable(:cwd).call(:reset)
    ctx.shareable(:env).call(:reset)
    ctx.display.append("session reset", style: :result)
  end

  shell.slash(:q,    description: "exit") { |_args, ctx| ctx.quit }
  shell.slash(:quit, description: "exit") { |_args, ctx| ctx.quit }

  shell.on_submit do |args, ctx|
    line = args.first
    parsed = ZshRunner.parse(line)

    case parsed[:kind]
    when :empty
      next
    when :error
      ctx.display.append(parsed[:message], style: :error)
    when :cd
      begin
        ctx.shareable(:cwd).call(:cd, parsed[:path])
        ctx.display.append("cwd: #{ctx.shareable(:cwd).call(:pwd)}", style: :dim)
      rescue Errno::ENOENT => e
        ctx.display.append("cd: #{e.message}", style: :error)
      end
    when :export
      ctx.shareable(:env).call(:set, parsed[:name], parsed[:value])
      ctx.display.append("#{parsed[:name]}=#{parsed[:value]}", style: :dim)
    when :unset
      ctx.shareable(:env).call(:unset, parsed[:name])
      ctx.display.append("unset #{parsed[:name]}", style: :dim)
    when :run
      ctx.state[:phase] = :working
      slot = ctx.display.open_live(style: :thinking)
      cwd = ctx.shareable(:cwd).call(:pwd)
      env = ctx.shareable(:env).call(:snapshot)
      begin
        status, elapsed = ZshRunner.run(
          parsed[:line],
          cwd: cwd,
          env: env,
          on_stdout: ->(l) { ctx.display.append(l.chomp, style: :result) },
          on_stderr: ->(l) { ctx.display.append(l.chomp, style: :error) },
          on_tick:   ->(s) { slot.update("running... #{s.round(1)}s") }
        )
        slot.discard
        mark = status.success? ? :ok : :ng
        ctx.display.append("exit #{status.exitstatus} · #{elapsed.round(2)}s", style: mark)
        ctx.state[:last_status] = status.exitstatus
        ctx.state[:last_elapsed] = elapsed
      rescue Errno::ENOENT
        slot.discard
        ctx.display.append("zsh not found in PATH", style: :error)
      ensure
        ctx.state[:phase] = :idle
      end
    end
  end
end
