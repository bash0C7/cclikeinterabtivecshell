require "test/unit"
require "tmpdir"
require "timeout"
require "baslash/debug/socket_protocol"

class TestSocketProtocol < Test::Unit::TestCase
  def setup
    @path = File.join(Dir.tmpdir, "baslash-test-sock-#{Process.pid}-#{rand(10000)}")
  end

  def teardown
    File.unlink(@path) if File.exist?(@path)
  end

  def test_round_trip_command
    server = Baslash::Debug::SocketProtocol::Server.new(@path)
    server_thread = Thread.new do
      server.serve do |cmd|
        { ok: true, echo: cmd[:op] }
      end
    end
    sleep 0.05
    Timeout.timeout(2.0) do
      client = Baslash::Debug::SocketProtocol::Client.new(@path)
      response = client.send_command({ op: "input", text: "hello" })
      assert_equal true, response[:ok] || response["ok"]
      assert_equal "input", response[:echo] || response["echo"]
    end
    server.shutdown
    server_thread.join(1.0)
  end
end
