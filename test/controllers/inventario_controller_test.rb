require "test_helper"

class InventarioControllerTest < ActionDispatch::IntegrationTest
  test "una cajera sin permiso no ajusta y queda reportado; un supervisor ajusta a su nombre" do
    post entrar_path, params: { usuario: "cajera", password: "secreto1" }
    get inventario_path
    assert_response :ok
    post movimientos_inventario_path, params: { producto_id: productos(:pechuga).id, tipo: "entrada", cantidad: "3", motivo: "" }
    assert_response :unprocessable_entity, "sin motivo no"
    get nuevo_movimiento_inventario_path
    assert_match "el movimiento se frena", response.body
    post movimientos_inventario_path, params: { producto_id: productos(:pechuga).id, tipo: "entrada", cantidad: "2", motivo: "llegó sin nadie" }
    assert_response :unprocessable_entity
    assert_match "Así no se mueve", response.body
    assert_equal BigDecimal("0"), Existencia.de(sucursales(:tienda), productos(:pechuga))
    reporte = Revision.last
    assert reporte.frenado?
    assert_equal [ productos(:pechuga), 25_800 ], [ reporte.revisable, reporte.valor_centavos ]
    assert_match "Movimiento frenado", reporte.descripcion
    post movimientos_inventario_path, params: { producto_id: productos(:pechuga).id, tipo: "entrada", cantidad: "2", motivo: "llegó sin nadie" }
    assert_equal 1, Revision.count, "el mismo intento no se reporta dos veces"
    delete salir_path
    post entrar_path, params: { usuario: "supervisora", password: "secreto1" }
    post movimientos_inventario_path, params: { producto_id: productos(:pechuga).id, tipo: "entrada", cantidad: "1", motivo: "llegó" }
    assert_redirected_to kardex_inventario_path(producto_id: productos(:pechuga).id, sucursal_id: sucursales(:tienda).id)
    assert_equal BigDecimal("1"), Existencia.de(sucursales(:tienda), productos(:pechuga))
    assert_equal 1, Revision.count, "con permiso, de fábrica, no hay nada que revisar"
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
