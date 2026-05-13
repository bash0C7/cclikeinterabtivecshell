# frozen_string_literal: true

require "open3"
require "shellwords"

module ZshRunner
  TICK_INTERVAL = 0.1

  module_function

  def parse(line)
    stripped = line.strip
    return {kind: :empty}.freeze if stripped.empty?

    tokens =
      begin
        Shellwords.split(stripped)
      rescue ArgumentError
        return {kind: :run, line: stripped}.freeze
      end

    head = tokens[0]
    rest = tokens[1..]

    case head
    when "cd"
      parse_cd(rest)
    when "export"
      parse_export(rest)
    when "unset"
      parse_unset(rest)
    else
      {kind: :run, line: stripped}.freeze
    end
  end

  def parse_cd(rest)
    if rest.empty?
      {kind: :cd, path: nil}.freeze
    elsif rest.length == 1
      arg = rest[0]
      if arg == "-"
        {kind: :error, message: "cd: - not supported in this example"}.freeze
      else
        {kind: :cd, path: arg}.freeze
      end
    else
      {kind: :error, message: "cd: too many arguments"}.freeze
    end
  end

  def parse_export(rest)
    if rest.empty?
      {kind: :error, message: "usage: export NAME=value"}.freeze
    elsif rest.length > 1
      {kind: :error, message: "usage: export NAME=value (only one assignment supported)"}.freeze
    else
      name, value = rest[0].split("=", 2)
      if value.nil? || name.nil? || name.empty?
        {kind: :error, message: "usage: export NAME=value"}.freeze
      else
        {kind: :export, name: name, value: value}.freeze
      end
    end
  end

  def parse_unset(rest)
    if rest.length != 1
      {kind: :error, message: "usage: unset NAME"}.freeze
    else
      {kind: :unset, name: rest[0]}.freeze
    end
  end

  def run(line, cwd:, env:, on_stdout:, on_stderr:, on_tick:)
    start = Time.now
    spawn_env = (env || {}).each_with_object({}) { |(k, v), h| h[k.to_s] = v.to_s }
    stdin, stdout, stderr, wait_thr = Open3.popen3(spawn_env, "zsh", "-c", line, chdir: cwd)
    stdin.close
    stdout.set_encoding("UTF-8", invalid: :replace, undef: :replace)
    stderr.set_encoding("UTF-8", invalid: :replace, undef: :replace)

    streams = [stdout, stderr]
    last_tick = start

    until streams.empty?
      ready, = IO.select(streams, nil, nil, TICK_INTERVAL)
      now = Time.now
      if now - last_tick >= TICK_INTERVAL
        on_tick.call(now - start)
        last_tick = now
      end
      next unless ready

      ready.each do |io|
        begin
          line_read = io.readline
        rescue EOFError
          streams.delete(io)
          next
        end
        if io == stdout
          on_stdout.call(line_read)
        else
          on_stderr.call(line_read)
        end
      end
    end

    status = wait_thr.value
    [status, Time.now - start]
  ensure
    [stdout, stderr].each { |io| io&.close unless io&.closed? }
  end
end
