require "test_helper"

class EscPosTest < ActiveSupport::TestCase
  setup do
    tienda = sucursales(:tienda)
    Inventario.mover!(sucursal: tienda, producto: productos(:catsup), tipo: "entrada", cantidad: 5, usuario: usuarios(:admin))
    @venta = Caja.cobrar!(sucursal: tienda, usuario: usuarios(:cajera), clave: "e", lineas: [ { producto_id: productos(:catsup).id, cantidad: 2 } ],
                          pagos: [ { forma: "efectivo", monto_centavos: 10_000 } ])
  end

  def texto(bytes) = bytes.dup.force_encoding("CP850").encode("UTF-8")

  test "el ticket arranca, elige PC850, lleva los renglones, el total en grande, el código y corta" do
    b = EscPos.ticket(@venta)
    assert_equal Encoding::BINARY, b.encoding
    assert b.start_with?("\e@\et\x02".b), "reinicia y elige PC850"
    assert_includes b, "\x1D!\x11".b, "total al doble"
    assert_includes b, "\x1Dk\x43\x0D#{@venta.codigo}".b, "EAN-13 del ticket"
    assert b.end_with?("\ed\x03\x1DV\x42\x00".b), "avanza y corta"
    t = texto(b)
    assert_match "Cátsup 1 kg", t, "los acentos llegan en PC850"
    assert_match(/  2 pz x \$42\.00 +\$84\.00\n/, t)
    assert_match @venta.folio, t
    assert t.lines.all? { |l| l.gsub(/[\x00-\x1F]./m, "").chomp.length <= 48 }, "nada pasa de 48 columnas"
  end

  test "en papel de 58 mm va a 32 columnas y sin código si se apagó" do
    Ajuste.guardar!("ticket.ancho" => "58", "ticket.mostrar_codigo" => "0")
    t = texto(EscPos.ticket(@venta))
    assert_includes t, "-" * 32 + "\n"
    assert_not_includes t, "-" * 33
    assert_not_includes EscPos.ticket(@venta), "\x1Dk".b
  end

  test "lo que no cabe en PC850 sale con un sustituto en vez de romper" do
    d = EscPos::Documento.new(columnas: 32).texto("10 € 漢 −5")
    assert_match "10 EUR ? -5", texto(d.to_s)
  end
end
