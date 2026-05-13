# frozen_string_literal: true

require "shellwords"
require "open3"

module ZshRunner
  TICK_INTERVAL = 0.1

  module_function

  def parse(line)
    stripped = line.to_s.strip
    return {kind: :empty}.freeze if stripped.empty?

    tokens =
      begin
        Shellwords.split(stripped)
      rescue ArgumentError
        return {kind: :run, line: stripped}.freeze
      end

    head = tokens[0]
    rest = tokens[1..] || []

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
end
