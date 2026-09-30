require "test_helper"

class ConteosTableroTest < ActionDispatch::IntegrationTest
  setup do
    @tienda = sucursales(:tienda)
    post entrar_path, params: { usuario: "supervisora", password: "secreto1" }
    Inventario.mover!(sucursal: @tienda, producto: productos(:catsup), tipo: "entrada", cantidad: 5, usuario: usuarios(:supervisora))
    Inventario.mover!(sucursal: @tienda, producto: productos(:pechuga), tipo: "entrada", cantidad: "1.5", usuario: usuarios(:supervisora))
  end

  test "conteo por pantalla: abrir, escanear, teclear, cerrar y ver el cargo" do
    post conteos_path, params: { responsable_id: usuarios(:cajera).id }
    conteo = Conteo.last
    assert_redirected_to conteo_path(conteo)
    4.times { post escanear_conteo_path(conteo), params: { codigo: "CATS" } }
    assert_match "una pieza más", flash[:notice]
    post escanear_conteo_path(conteo), params: { codigo: "PECH" }
    assert_match "tecléalo a mano", flash[:alert]
    post manual_conteo_path(conteo), params: { producto_id: productos(:pechuga).id, cantidad: "1.5" }
    get conteo_path(conteo)
    assert_select "td", /Cátsup/
    post cerrar_conteo_path(conteo)
    assert_equal 4_200, conteo.reload.faltante_centavos
    get cargos_path
    assert_select "td", /Cajera/
    post resolver_cargo_path(Cargo.last, estado: "cobrado")
    assert_equal "cobrado", Cargo.last.reload.estado
    get conteos_path
    assert_select "td", /#{conteo.folio}/
  end

  test "conteo parcial por línea desde la pantalla, y el aviso de que toca contar" do
    get new_conteo_path
    assert_select "input[name=alcance][value=parcial]"
    assert_select "select[name=linea] option", /Abarrotes/
    post conteos_path, params: { responsable_id: usuarios(:cajera).id, alcance: "parcial", linea: "Abarrotes" }
    conteo = Conteo.last
    assert conteo.parcial?
    assert_equal [ productos(:catsup) ], conteo.lineas.map(&:producto)
    post escanear_conteo_path(conteo), params: { codigo: "PECH" }
    assert_match "tecléalo a mano", flash[:alert]
    post manual_conteo_path(conteo), params: { producto_id: productos(:pechuga).id, cantidad: "1" }
    assert_match "no está en este conteo parcial", flash[:alert]
    get conteo_path(conteo)
    assert_select "span.badge", /parcial · 1 producto/
    post cerrar_conteo_path(conteo)
    assert_equal "cerrado", conteo.reload.estado
    get conteos_path
    assert_select "p", { count: 0, text: /Toca contar/ }
    @tienda.update!(dias_conteo: 3)
    conteo.update_columns(cerrado_en: 4.days.ago)
    get conteos_path
    assert_select "p", /Toca contar/
    get root_path
    assert_select "p", /Toca contar/
    post conteos_path, params: { responsable_id: usuarios(:cajera).id, alcance: "parcial" }
    assert_match "al menos un producto", flash[:alert]
  end

  test "el inicio es el tablero y ventas por producto con CSV; sin permiso, bienvenida" do
    Caja.cobrar!(sucursal: @tienda, usuario: usuarios(:cajera), clave: "tb", lineas: [ { producto_id: productos(:catsup).id, cantidad: 2 } ], pagos: [ { forma: "efectivo", monto_centavos: 10_000 } ])
    get root_path
    assert_response :ok
    assert_match "$84.00", response.body
    get ventas_por_producto_path
    assert_select "td", /Cátsup/
    get ventas_por_producto_path(format: :csv)
    assert_match "CATS;", response.body
    delete salir_path
    post entrar_path, params: { usuario: "cajera", password: "secreto1" }
    get root_path
    assert_response :ok
    assert_no_match "$84.00", response.body
    assert_match "Cajera", response.body
    get ventas_por_producto_path
    assert_response :forbidden
  end
end
