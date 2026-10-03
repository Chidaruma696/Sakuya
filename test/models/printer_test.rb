require "test_helper"
require "socket"

class PrinterTest < ActiveSupport::TestCase
  # A fake "thermal printer": a port that keeps whatever is written to it.
  def with_thermal
    server = TCPServer.new("127.0.0.1", 0)
    received = +"".b
    thread = Thread.new { c = server.accept; received << c.read; c.close }
    yield "127.0.0.1:#{server.addr[1]}"
    thread.join(3)
    received
  ensure
    server&.close
  end

  test "sends the bytes to the network thermal printer" do
    received = with_thermal { |address| Printer.deliver!(address, "\e@hello".b) }
    assert_equal "\e@hello".b, received
  end

  test "if it does not answer, it says so" do
    server = TCPServer.new("127.0.0.1", 0)
    port = server.addr[1]
    server.close
    assert_match "does not answer", assert_raises(Printer::Error) { Printer.deliver!("127.0.0.1:#{port}", "x") }.message
    assert_match "has no address", assert_raises(Printer::Error) { Printer.deliver!("", "x") }.message
  end

  test "a branch that prints over the network needs address:port" do
    store = branches(:store)
    store.printer = "network"
    assert_not store.valid?
    store.network_printer = "192.168.1.50:9100"
    assert store.valid?
    store.printer = "fax"
    assert_not store.valid?
  end
end
