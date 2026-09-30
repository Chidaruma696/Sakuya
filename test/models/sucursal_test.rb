require "test_helper"

class SucursalTest < ActiveSupport::TestCase
  test "hay una matriz y el resto son tiendas" do
    assert_equal sucursales(:matriz), Sucursal.matriz
    assert_not sucursales(:tienda).matriz?
    assert_not Sucursal.new(codigo: "X", nombre: "X", tipo: "bodega").valid?
  end
end
