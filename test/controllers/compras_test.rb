require "test_helper"

# Pantallas de Compras: cinta, alta de proveedor, recepción escaneando el código del proveedor,
# factura ligada, cuentas por pagar con pago desde la gaveta, y el módulo apagado.
class ComprasControllerTest < ActionDispatch::IntegrationTest
  setup do
    post entrar_path, params: { usuario: "admin", password: "secreto1" }
    @matriz = sucursales(:matriz)
  end

  test "el flujo completo: proveedor, recepción por código, factura ligada y pago" do
    get root_path
    assert_select "aside[data-lateral-target=panel] div", /Compras/

    post proveedores_path, params: { proveedor: { nombre: "Cátsup y más", dias_credito: 30, telefono: "555" } }
    prov = Proveedor.find_by!(nombre: "Cátsup y más")
    assert_redirected_to proveedores_path

    get buscar_productos_path(q: "750100655901"), headers: { "Accept" => "application/json" }
    lista = JSON.parse(response.body)
    assert_equal [ productos(:catsup).id ], lista.map { |p| p["id"] }, "el código del proveedor resuelve el producto"

    post recepciones_path, params: { recepcion: { proveedor_id: prov.id, remision: "R-1", fecha: Date.current, clave: "k1",
                                                  lineas_attributes: { "0" => { producto_id: productos(:catsup).id, cantidad: "12", cajas: "1" } } } }
    r = Recepcion.last
    assert_redirected_to recepcion_path(r)
    assert_equal 12, Existencia.de(@matriz, productos(:catsup))
    get recepcion_path(r)
    assert_select "h1", /RC-/
    assert_select "td", /Cátsup/

    post facturas_path, params: { factura: { proveedor_id: prov.id, folio: "B-9", fecha: Date.current, recepcion_ids: [ r.id ],
                                             lineas_attributes: { "0" => { producto_id: productos(:catsup).id, cantidad: "12", precio: "25" } } } }
    f = FacturaProveedor.last
    assert_redirected_to factura_path(f)
    assert_equal 300_00, f.monto_centavos
    assert_equal f, r.reload.factura
    get factura_path(f)
    assert_select "td", /✓/

    get cuentas_path
    assert_select "td", /Cátsup y más/
    get cuenta_path(prov)
    assert_select "p", /No hay caja abierta/
    Corte.abrir!(sucursal: @matriz, usuario: usuarios(:admin), fondo_centavos: 500_00)
    post pagar_cuenta_path(prov), params: { monto: "300", forma: "efectivo", factura_proveedor_id: f.id }
    assert_redirected_to cuenta_path(prov)
    assert_equal 0, prov.saldo_centavos
    assert_equal 200_00, Corte.abierto_en(@matriz).efectivo_esperado_centavos
  end

  test "candado de compras: facturar más de lo recibido exige motivo y queda por revisar; el estado de recepción se ve" do
    prov = Proveedor.create!(nombre: "Granja", dias_credito: 0)
    r = Compras.recibir!(sucursal: @matriz, proveedor: prov, usuario: usuarios(:admin), lineas: [ { producto_id: productos(:catsup).id, cantidad: "12" } ])
    lineas = { "0" => { producto_id: productos(:catsup).id, cantidad: "15", precio: "30" } }
    # Sin candado solo se enseña la diferencia.
    post facturas_path, params: { factura: { proveedor_id: prov.id, folio: "F-1", fecha: Date.current, recepcion_ids: [ r.id ], lineas_attributes: lineas } }
    assert_redirected_to factura_path(FacturaProveedor.last)
    assert_equal 0, Revision.count
    assert_equal "parcial", FacturaProveedor.last.estado_recepcion
    Ajuste.guardar!("compras.candado_recibido" => "1")
    # El admin tiene compras.exceder: pasa sin motivo y sin revisión.
    post facturas_path, params: { factura: { proveedor_id: prov.id, folio: "F-2", fecha: Date.current, lineas_attributes: lineas } }
    assert_redirected_to factura_path(FacturaProveedor.last)
    assert_equal 0, Revision.count
    assert_equal "sin_recepcion", FacturaProveedor.last.estado_recepcion
    roles(:administrador).update!(permisos: Permiso::CLAVES.keys - [ "compras.exceder" ])
    get new_factura_path
    assert_select "input[name='factura[motivo]']"
    assert_select "input[name='factura[recepcion_ids][]']", { count: 0 }, "la recepción ya se ligó a F-1"
    post facturas_path, params: { factura: { proveedor_id: prov.id, folio: "F-3", fecha: Date.current, lineas_attributes: lineas } }
    assert_match "más de lo recibido", flash[:alert]
    assert_nil FacturaProveedor.find_by(folio: "F-3")
    r2 = Compras.recibir!(sucursal: @matriz, proveedor: prov, usuario: usuarios(:admin), lineas: [ { producto_id: productos(:catsup).id, cantidad: "10" } ])
    post facturas_path, params: { factura: { proveedor_id: prov.id, folio: "F-3", fecha: Date.current, recepcion_ids: [ r2.id ], motivo: "el proveedor cobra la merma", lineas_attributes: lineas } }
    f = FacturaProveedor.find_by!(folio: "F-3")
    assert_redirected_to factura_path(f)
    assert_match "queda por revisar", flash[:notice]
    rev = Revision.last
    assert_equal f, rev.revisable
    assert_equal 15_000, rev.valor_centavos, "5 de más × 30.00"
    assert_match "Cátsup 1 kg +5", rev.motivo
    assert_match "con más de lo recibido", rev.descripcion
    post facturas_path, params: { factura: { proveedor_id: prov.id, folio: "F-4", fecha: Date.current, monto: "80" } }
    assert_equal "completa", FacturaProveedor.find_by!(folio: "F-4").estado_recepcion, "sin renglones no hay qué comparar"
    get facturas_path
    assert_select "span", /recibida parcial/
    assert_select "span", /sin recepción/
    get ajustes_seccion_path("compras")
    assert_select "input[name='ajuste[compras.candado_recibido]'][checked]"
  end

  test "con el módulo apagado sus pantallas lo dicen y desaparece de la cinta" do
    Modulo.guardar!(Modulo::OPCIONALES - %w[compras], comprobar: false)
    get root_path
    assert_select "aside[data-lateral-target=panel] div", { text: /Compras/, count: 0 }
    get proveedores_path
    assert_response :not_found

    Modulo.guardar!(Modulo::OPCIONALES - %w[almacenes], comprobar: false)
    get root_path
    assert_select "aside[data-lateral-target=panel] div", { text: /Almacenes/, count: 0 }
    assert_select "aside[data-lateral-target=panel] div", /Compras/
    get new_traspaso_path
    assert_response :not_found
    get new_admin_sucursal_path
    assert_select "option", { text: /Almacén/, count: 0 }
  ensure
    Modulo.guardar!(Modulo::OPCIONALES, comprobar: false)
  end

  test "la cajera no entra a compras" do
    post entrar_path, params: { usuario: "cajera", password: "secreto1" }
    get cuentas_path
    assert_response :forbidden
  end
end
