require 'rinda/tuplespace'

class TupleSpace4Ractor
  class Impl
    def initialize
      @ts = Rinda::TupleSpace.new #FIXME
      @read_waiter = []
      @take_waiter = []
    end

    def do_take(port, pattern)
      tuple = @ts.take(pattern, 0)
      port << tuple
      true
    rescue Rinda::RequestExpiredError
      false
    end

    def do_read(port, pattern)
      tuple = @ts.read(pattern, 0)
      port << tuple
      true
    rescue Rinda::RequestExpiredError
      false
    end

    def do_write(tuple)
      @ts.write(tuple)
      @read_waiter.delete_if {|port, pattern| do_read(port, pattern)}
      taken = false
      @take_waiter.delete_if {|port, pattern| 
        break if taken
        taken = do_take(port, pattern)
      }
    end

    def main_loop
      while true
        command, tuple, port = Ractor.receive
        case command
        when :read
          @read_waiter << [port, tuple] unless do_read(port, tuple)
        when :take
          @take_waiter << [port, tuple] unless do_take(port, tuple)
        when :write
          do_write(tuple)
        end
      end
    end
  end

  def initialize
    @ractor = Ractor.new { Impl.new.main_loop }
    log_init
  end

  def take(pattern)
    port = Ractor::Port.new
    @ractor << [:take, pattern, port]
    port.receive
  end

  def read(pattern)
    port = Ractor::Port.new
    @ractor << [:read, pattern, port]
    port.receive
  end

  def write(tuple)
    @ractor << [:write, tuple]
    tuple
  end

  def make_loginfo
    rid = Ractor.current.to_s.scan(/Ractor:#(\d+)/)&.first&.first.to_i
    loc = caller_locations(2,1).map {|x| [x.path, x.lineno]}.first
    [rid] + loc
  end

  def _name; @ractor; end

  def log_init
    write([_name, :first, 0])
    write([_name, :last, 0])
  end

  def log_write(any)
    _, _, last = take([_name, :last, nil])
    write([_name, :log, last, make_loginfo, Marshal.dump(any)])
    write([_name, :last, last + 1])
    any
  end
  alias log log_write

  def log_take
    _, _, first = take([_name, :first, nil])
    _, _, _, info, tuple = take([_name, :log, first, nil, nil])
    write([_name, :first, first + 1])
    return info, Marshal.load(tuple)
  end

  def log_read_at(index)
    _, _, _, info, tuple = read([_name, :log, index, nil, nil])
    return info, Marshal.load(tuple)
  end

  def break(any=nil)
    info = make_loginfo
    write([_name, :break, info, Marshal.dump(any)])
    _, _, _, tuple = take([_name, :continue, info, nil])
    Marshal.load(tuple)
  end

  def watch_break(info)
    _, _, info, any = take([_name, :break, info, nil])
    return info, Marshal.load(any)
  end

  def continue(info, any=nil)
    write([_name, :continue, info, Marshal.dump(any)])
  end

  Aether = Ractor.make_shareable(self.new)
end
