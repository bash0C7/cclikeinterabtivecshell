# frozen_string_literal: true

module Cclikesh
  class ShareableRef
    attr_reader :name

    def self.spawn(name, &block)
      object = block.call
      ractor = Ractor.new(object) do |obj|
        loop do
          msg = Ractor.receive
          break if msg == :stop
          reply_to, method, *args = msg
          begin
            result = obj.public_send(method, *args)
            reply_to.send([:ok, result])
          rescue => e
            reply_to.send([:error, e.class.name, e.message])
          end
        end
      end
      new(name, ractor)
    end

    def initialize(name, ractor)
      @name = name
      @ractor = ractor
    end

    def call(method, *args)
      frozen_args = args.map { |a| a.frozen? ? a : a.dup.freeze }.freeze
      @ractor.send([Ractor.current, method, *frozen_args])
      tag, *rest = Ractor.receive
      if tag == :error
        raise RuntimeError, "ShareableRef(#{@name}).#{method} raised #{rest[0]}: #{rest[1]}"
      end
      rest[0]
    end

    def stop
      @ractor.send(:stop) rescue nil
    end
  end
end
