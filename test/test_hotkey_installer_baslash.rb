# frozen_string_literal: true

require_relative "test_helper"
require "logger"
require "stringio"
require "reline"
require "baslash/slash_registry"
require "baslash/hotkey_installer"

class TestHotkeyInstallerBaslash < Test::Unit::TestCase
  def setup
    @log_io = StringIO.new
    @logger = Logger.new(@log_io)
    @registry = Baslash::SlashRegistry.new
    @builder = StubBuilder.new(@registry, @logger)
    Reline.core.config.reset
  end

  def test_install_skips_entries_without_hotkey
    @registry.register(:plain, proc {}, description: "plain")
    Baslash::HotkeyInstaller.install(@builder)
    assert_empty @log_io.string
  end

  def test_install_defines_method_on_line_editor
    @registry.register(:reset, proc {}, description: "reset", hotkey: "C-g")
    Baslash::HotkeyInstaller.install(@builder)
    assert Reline::LineEditor.method_defined?(:__baslash_hotkey_reset) ||
           Reline::LineEditor.private_method_defined?(:__baslash_hotkey_reset),
           "expected __baslash_hotkey_reset to be defined on Reline::LineEditor"
  end

  def test_install_warns_on_duplicate_byte_sequence
    @registry.register(:reset, proc {}, description: "reset", hotkey: "C-g")
    @registry.register(:other, proc {}, description: "other", hotkey: "C-g")
    Baslash::HotkeyInstaller.install(@builder)
    assert_includes @log_io.string, "hotkey conflict"
    assert_includes @log_io.string, "C-g"
  end

  def test_install_is_idempotent_across_method_redefinition
    @registry.register(:reset, proc {}, description: "reset", hotkey: "C-g")
    Baslash::HotkeyInstaller.install(@builder)
    assert_nothing_raised { Baslash::HotkeyInstaller.install(@builder) }
  end

  def test_hotkey_method_inserts_command_and_finishes
    @registry.register(:marker, proc {}, description: "marker", hotkey: "C-g")
    Baslash::HotkeyInstaller.install(@builder)
    fake = FakeLineEditor.new(buffer: [""], line_index: 0)
    fake.send(:__baslash_hotkey_marker, [7])
    assert_equal ["/marker"], fake.buffer
    assert_equal "/marker".bytesize, fake.byte_pointer
    assert fake.finished?
  end

  def test_hotkey_method_noop_when_buffer_nonempty
    @registry.register(:marker, proc {}, description: "marker", hotkey: "C-g")
    Baslash::HotkeyInstaller.install(@builder)
    fake = FakeLineEditor.new(buffer: ["already typing"], line_index: 0)
    fake.send(:__baslash_hotkey_marker, [7])
    assert_equal ["already typing"], fake.buffer
    refute fake.finished?
  end

  def test_hotkey_method_noop_when_multiline_edit
    @registry.register(:marker, proc {}, description: "marker", hotkey: "C-g")
    Baslash::HotkeyInstaller.install(@builder)
    fake = FakeLineEditor.new(buffer: ["", "second"], line_index: 0)
    fake.send(:__baslash_hotkey_marker, [7])
    assert_equal ["", "second"], fake.buffer
    refute fake.finished?
  end

  StubBuilder = Struct.new(:slash_registry, :logger)

  # Test double for Reline::LineEditor. Exposes the ivars and helpers our
  # installed method uses (@buffer_of_lines, @line_index, current_line,
  # set_current_line, finish). Falls through to the real instance method
  # via instance_method.bind(self).call(...) so we test the actual code
  # the installer defined.
  class FakeLineEditor
    attr_reader :byte_pointer

    def initialize(buffer:, line_index:)
      @buffer_of_lines = buffer
      @line_index      = line_index
      @byte_pointer    = 0
      @finished        = false
    end

    def buffer; @buffer_of_lines; end
    def current_line; @buffer_of_lines[@line_index]; end

    def set_current_line(line, ptr = nil)
      @buffer_of_lines[@line_index] = line
      @byte_pointer = ptr || line.bytesize
    end

    def finish; @finished = true; end
    def finished?; @finished; end

    def respond_to_missing?(name, include_private = false)
      Reline::LineEditor.method_defined?(name, true) ||
        Reline::LineEditor.private_method_defined?(name) ||
        super
    end

    def method_missing(name, *args, &blk)
      if Reline::LineEditor.method_defined?(name, true) || Reline::LineEditor.private_method_defined?(name)
        Reline::LineEditor.instance_method(name).bind(self).call(*args, &blk)
      else
        super
      end
    end
  end
end
