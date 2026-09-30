require "test_helper"

class ProductoTest < ActiveSupport::TestCase
  test "asigna el PLU siguiente al mayor, nunca por debajo de 90000" do
    p = Producto.create!(clave: "NUEVO", nombre: "Nuevo", unidad: "kg", precio: 10)
    assert_equal 90003, p.plu
  end

  test "el precio se guarda en centavos enteros" do
    p = Producto.new(clave: "X", nombre: "X", unidad: "kg")
    p.precio = "129.999"
    assert_equal 13000, p.precio_centavos
    assert_equal BigDecimal("130"), p.precio
  end

  test "rechaza unidad y precio inválidos" do
    p = Producto.new(clave: "X", nombre: "X", unidad: "galon", precio_centavos: -1)
    assert_not p.valid?
    assert p.errors[:unidad].any?
    assert p.errors[:precio_centavos].any?
  end

  test "los códigos del proveedor se normalizan a dígitos y no se repiten" do
    c = productos(:pechuga).codigos_barras.create(codigo: "750 1006 559019")
    assert_not c.persisted?, "el código de la cátsup ya existe"
    c2 = productos(:pechuga).codigos_barras.create!(codigo: " 0012345678905 ")
    assert_equal "0012345678905", c2.codigo
  end
end

class UnidadesTest < ActiveSupport::TestCase
  test "kilo, litro y metro van en fracciones; la pieza entera" do
    litro = Producto.create!(clave: "LECH", nombre: "Leche a granel", unidad: "litro", precio: 22)
    metro = Producto.create!(clave: "CABL", nombre: "Cable", unidad: "metro", precio: 9)
    assert litro.fraccionable? && metro.fraccionable? && productos(:pechuga).fraccionable?
    assert_not productos(:catsup).fraccionable?
    assert_equal 3, litro.decimales
    assert_equal "l", litro.unidad_corta
    assert_equal "m", metro.unidad_corta
    assert_not litro.kg?, "la báscula solo pesa kilos"
    Inventario.mover!(sucursal: sucursales(:tienda), producto: litro, tipo: "entrada", cantidad: 10, usuario: usuarios(:admin))
    venta = Caja.cobrar!(sucursal: sucursales(:tienda), usuario: usuarios(:admin), clave: "lt1", lineas: [ { producto_id: litro.id, cantidad: "1.5" } ],
                         pagos: [ { forma: "efectivo", monto_centavos: 3_300 } ])
    assert_equal BigDecimal("1.5"), venta.lineas.first.cantidad
  end
end
