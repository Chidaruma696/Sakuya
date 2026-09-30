require "test_helper"

class InventarioTest < ActiveSupport::TestCase
  setup do
    @tienda = sucursales(:tienda)
    @pechuga = productos(:pechuga)
    @cajera = usuarios(:cajera)
  end

  test "una entrada crea la existencia y deja el saldo en el kardex" do
    m = Inventario.mover!(sucursal: @tienda, producto: @pechuga, tipo: "entrada", cantidad: "12.5", usuario: @cajera, motivo: "prueba")
    assert_equal BigDecimal("12.5"), Existencia.de(@tienda, @pechuga)
    assert_equal BigDecimal("12.5"), m.saldo
    Inventario.mover!(sucursal: @tienda, producto: @pechuga, tipo: "venta", cantidad: "2.250", usuario: @cajera)
    assert_equal BigDecimal("10.25"), Existencia.de(@tienda, @pechuga)
  end

  test "nunca deja la existencia en negativo" do
    Inventario.mover!(sucursal: @tienda, producto: @pechuga, tipo: "entrada", cantidad: 1, usuario: @cajera)
    assert_raises(Inventario::SinExistencia) do
      Inventario.mover!(sucursal: @tienda, producto: @pechuga, tipo: "venta", cantidad: "1.001", usuario: @cajera)
    end
    assert_equal BigDecimal("1"), Existencia.de(@tienda, @pechuga)
    assert_equal 1, Movimiento.count
  end

  test "rechaza cantidades cero o negativas y tipos desconocidos" do
    assert_raises(ArgumentError) { Inventario.mover!(sucursal: @tienda, producto: @pechuga, tipo: "entrada", cantidad: 0, usuario: @cajera) }
    assert_raises(ArgumentError) { Inventario.mover!(sucursal: @tienda, producto: @pechuga, tipo: "regalo", cantidad: 1, usuario: @cajera) }
  end

  test "las existencias son por sucursal" do
    Inventario.mover!(sucursal: sucursales(:matriz), producto: @pechuga, tipo: "entrada", cantidad: 100, usuario: usuarios(:admin))
    assert_equal BigDecimal("0"), Existencia.de(@tienda, @pechuga)
  end

  test "el kardex no se edita ni se borra" do
    m = Inventario.mover!(sucursal: @tienda, producto: @pechuga, tipo: "entrada", cantidad: 1, usuario: @cajera)
    assert_raises(ActiveRecord::ReadOnlyRecord) { m.update!(cantidad: 5) }
    assert_raises(ActiveRecord::ReadOnlyRecord) { m.destroy! }
  end
end
