require "test_helper"

class CorteTest < ActiveSupport::TestCase
  setup do
    @corte = cortes(:tienda_abierto) # fondo 500.00, sin ventas
  end

  test "las denominaciones salen de Ajustes en centavos, de mayor a menor y sin repetidas" do
    assert_equal 100_000, Corte.denominaciones.first
    assert_equal 50, Corte.denominaciones.last
    Ajuste.guardar!("caja.denominaciones" => "20, 100, 20, 0.50")
    assert_equal [ 10_000, 2_000, 50 ], Corte.denominaciones
    assert_raises(ArgumentError) { Ajuste.guardar!("caja.denominaciones" => "100;50") }
  end

  test "cerrar contando billetes: el total sale del desglose y queda guardado" do
    @corte.cerrar!(usuario: usuarios(:cajera), desglose: { "50000" => "1", "10000" => "0", "999" => "5", "2000" => "2" })
    assert_equal 54_000, @corte.contado_centavos, "1 × 500 + 2 × 20; el 999 no es denominación y se ignora"
    assert_equal 4_000, @corte.diferencia_centavos
    assert_equal({ "50000" => 1, "2000" => 2 }, @corte.reload.desglose)
    assert_equal "1 × $500.00, 2 × $20.00", @corte.desglose_texto
  end

  test "sin desglose se cierra con el total tecleado y sin desglose guardado" do
    @corte.cerrar!(contado_centavos: 49_000, usuario: usuarios(:cajera), desglose: {})
    assert_equal(-1_000, @corte.diferencia_centavos)
    assert_nil @corte.reload.desglose
    assert_equal "", @corte.desglose_texto
  end

  test "el tope de diferencia vale 0 de fábrica (sin tope) y se compara en valor absoluto" do
    assert_not Corte.excede_tope?(-99_999)
    Ajuste.guardar!("caja.tope_diferencia" => "50")
    assert_equal 5_000, Corte.tope_diferencia_centavos
    assert_not Corte.excede_tope?(5_000)
    assert Corte.excede_tope?(-5_001)
  end
end
