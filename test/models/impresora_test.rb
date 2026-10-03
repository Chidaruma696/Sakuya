require "test_helper"
require "socket"

class ImpresoraTest < ActiveSupport::TestCase
  # Una "térmica" de mentira: un puerto que guarda lo que le escriben.
  def con_termica
    servidor = TCPServer.new("127.0.0.1", 0)
    recibido = +"".b
    hilo = Thread.new { c = servidor.accept; recibido << c.read; c.close }
    yield "127.0.0.1:#{servidor.addr[1]}"
    hilo.join(3)
    recibido
  ensure
    servidor&.close
  end

  test "manda los bytes a la térmica de red" do
    recibido = con_termica { |dir| Impresora.enviar!(dir, "\e@hola".b) }
    assert_equal "\e@hola".b, recibido
  end

  test "si no contesta, lo dice" do
    servidor = TCPServer.new("127.0.0.1", 0)
    puerto = servidor.addr[1]
    servidor.close
    assert_match "no contesta", assert_raises(Impresora::Error) { Impresora.enviar!("127.0.0.1:#{puerto}", "x") }.message
    assert_match "no tiene la dirección", assert_raises(Impresora::Error) { Impresora.enviar!("", "x") }.message
  end

  test "la sucursal pide dirección:puerto si imprime por red" do
    tienda = sucursales(:tienda)
    tienda.impresora = "red"
    assert_not tienda.valid?
    tienda.impresora_red = "192.168.1.50:9100"
    assert tienda.valid?
    tienda.impresora = "fax"
    assert_not tienda.valid?
  end
end
