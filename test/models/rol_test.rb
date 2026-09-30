require "test_helper"

class RolTest < ActiveSupport::TestCase
  test "el comodín total y el de módulo cubren las claves" do
    assert roles(:administrador).permite?("admin.usuarios")
    assert roles(:supervisor).permite?("caja.bajar_precio")
    assert_not roles(:supervisor).permite?("admin.usuarios")
    assert roles(:cajero).permite?("caja.vender")
    assert_not roles(:cajero).permite?("caja.bajar_precio")
  end

  test "una clave que no existe nunca se permite, ni con comodín" do
    assert_not roles(:administrador).permite?("caja.inventada")
  end

  test "rechaza permisos desconocidos" do
    rol = Rol.new(nombre: "raro", permisos: [ "caja.vender", "magia.*" ])
    assert_not rol.valid?
    assert_match "magia.*", rol.errors[:permisos].first
  end
end
