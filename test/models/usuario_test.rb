require "test_helper"

class UsuarioTest < ActiveSupport::TestCase
  test "puede? depende del rol y de estar activo" do
    assert usuarios(:cajera).puede?("caja.vender")
    assert_not usuarios(:cajera).puede?("caja.bajar_precio")
    assert_not usuarios(:inactivo).puede?("caja.vender")
  end

  test "el nombre de usuario es en minúsculas y sin espacios" do
    u = Usuario.new(nombre: "X", usuario: "Con Espacios", password: "12345678", rol: roles(:cajero), sucursal: sucursales(:tienda))
    assert_not u.valid?
    assert u.errors[:usuario].any?
  end
end
