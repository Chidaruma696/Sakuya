require "test_helper"

class TraspasosControllerTest < ActionDispatch::IntegrationTest
  setup do
    post entrar_path, params: { usuario: "admin", password: "secreto1" }
    @matriz = sucursales(:matriz)
    @frio = Sucursal.create!(codigo: "FRI", nombre: "Frigorífico", tipo: "almacen", limite_efectivo_centavos: 1)
    Inventario.mover!(sucursal: @matriz, producto: productos(:catsup), tipo: "entrada", cantidad: 100, usuario: usuarios(:admin))
  end

  test "un traspaso a granel desde la pantalla, y la cinta del almacén no tiene caja ni etiquetas" do
    get new_traspaso_path
    assert_select "option", /Frigorífico · almacén/
    post traspasos_path, params: { traspaso: { sucursal_origen_id: @matriz.id, sucursal_destino_id: @frio.id, fecha: Date.current, clave: "z1",
                                               lineas_attributes: { "0" => { producto_id: productos(:catsup).id, cantidad: "60", cajas: "5" } } } }
    t = Traspaso.last
    assert_redirected_to traspaso_path(t)
    assert_equal 60, Existencia.de(@frio, productos(:catsup))
    get traspaso_path(t)
    assert_select "h1", /TG-/
    get traspasos_path
    assert_select "td", /Frigorífico/

    usuarios(:admin).update!(sucursal: @frio)
    get root_path
    assert_select "aside[data-lateral-target=panel] div", { text: /Caja/, count: 0 }
    assert_select "aside[data-lateral-target=panel] div", { text: /Etiquetas/, count: 0 }
    assert_select "aside[data-lateral-target=panel] div", /Almacenes/
  end
end
