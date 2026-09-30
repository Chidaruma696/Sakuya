require "test_helper"

class InventarioControllerTest < ActionDispatch::IntegrationTest
  test "una cajera ajusta y queda por revisar; un supervisor ajusta a su nombre" do
    post entrar_path, params: { usuario: "cajera", password: "secreto1" }
    get inventario_path
    assert_response :ok
    post movimientos_inventario_path, params: { producto_id: productos(:pechuga).id, tipo: "entrada", cantidad: "3", motivo: "" }
    assert_response :unprocessable_entity, "sin motivo no"
    post movimientos_inventario_path, params: { producto_id: productos(:pechuga).id, tipo: "entrada", cantidad: "2", motivo: "llegó sin nadie" }
    assert_redirected_to kardex_inventario_path(producto_id: productos(:pechuga).id, sucursal_id: sucursales(:tienda).id)
    assert_equal BigDecimal("2"), Existencia.de(sucursales(:tienda), productos(:pechuga))
    assert_match "por revisar", Movimiento.last.motivo
    assert_equal Movimiento.last, Revision.last.revisable
    assert_equal 25_800, Revision.last.valor_centavos
    delete salir_path
    post entrar_path, params: { usuario: "supervisora", password: "secreto1" }
    post movimientos_inventario_path, params: { producto_id: productos(:pechuga).id, tipo: "entrada", cantidad: "1", motivo: "llegó" }
    assert_redirected_to kardex_inventario_path(producto_id: productos(:pechuga).id, sucursal_id: sucursales(:tienda).id)
    assert_equal BigDecimal("3"), Existencia.de(sucursales(:tienda), productos(:pechuga))
    assert_equal 1, Revision.count
    assert_match "Supervisora", Movimiento.last.motivo
    follow_redirect!
    assert_select "td", /Entrada/
  end

  test "una tienda no puede mirar otra sucursal, la matriz sí" do
    post entrar_path, params: { usuario: "cajera", password: "secreto1" }
    get inventario_path(sucursal_id: sucursales(:matriz).id)
    assert_select "h1", /Tienda 1/
    delete salir_path
    post entrar_path, params: { usuario: "admin", password: "secreto1" }
    get inventario_path(sucursal_id: sucursales(:tienda).id)
    assert_select "h1", /Tienda 1/
  end

  test "un ajuste de salida sin existencia avisa sin romper" do
    post entrar_path, params: { usuario: "admin", password: "secreto1" }
    post movimientos_inventario_path, params: { producto_id: productos(:pechuga).id, tipo: "merma", cantidad: "1", motivo: "x" }
    assert_response :unprocessable_entity
    assert_match "insuficiente", response.body
  end
end
