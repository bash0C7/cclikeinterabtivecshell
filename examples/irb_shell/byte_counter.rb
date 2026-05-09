# frozen_string_literal: true

class ByteCounter
  attr_reader :bytes

  def initialize
    @bytes = 0
  end

  def add(n)
    @bytes += n
  end

  def reset
    @bytes = 0
  end

  def human
    if @bytes < 1024
      "#{@bytes}b"
    elsif @bytes < 1024 * 1024
      "#{(@bytes / 1024.0).round(1)}kb"
    else
      "#{(@bytes / (1024.0 * 1024.0)).round(1)}mb"
    end
  end
end
