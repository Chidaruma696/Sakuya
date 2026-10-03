require "test_helper"

class ReglasControllerTest < ActionDispatch::IntegrationTest
  setup { post entrar_path, params: { usuario: "admin", password: "secreto1" } }

  test "el editor prueba con un caso, guarda solo lo que decide y restaura" do
    get ajustes_path
    assert_select "a[href=?]", regla_editar_path("corte")
    get regla_editar_path("corte")
    assert_response :ok
    assert_select "textarea#codigo", /reject :over-limit/
    assert_select "input#esperado[value='500.00']", 1, "de entrada, lo que espera el corte abierto"

    codigo = '(if (< (difference) 0) (reject "falta") (allow))'
    post regla_guardar_path("corte"), params: { probar: "1", codigo: codigo, esperado: "500", contado: "480" }
    assert_response :ok
    assert_select "#decision", /Se frena: falta/
    assert_select "#inventado_si[checked]", 0, "de entrada, el corte de verdad"
    assert_equal 0, Regla.count, "probar no guarda"

    post regla_guardar_path("corte"), params: { codigo: "(allow" }
    assert_response :unprocessable_entity
    assert_select "p", /falta cerrar/
    post regla_guardar_path("corte"), params: { codigo: "(+ 1 2)" }
    assert_response :unprocessable_entity
    assert_select "p", /terminó en 3/
    assert_equal 0, Regla.count

    post regla_guardar_path("corte"), params: { codigo: codigo }
    assert_redirected_to regla_editar_path("corte")
    assert_equal codigo, Regla.vigente("corte").codigo
    primera = Regla.vigente("corte")
    post regla_guardar_path("corte"), params: { codigo: "(allow)" }
    post regla_restaurar_path("corte", primera)
    assert_equal codigo, Regla.vigente("corte").codigo
    assert_equal 3, Regla.count
    assert_equal 0, Regla.de("tablero").count, "cada gancho lleva sus versiones"
  end

  test "el editor del precio prueba con un producto del catálogo" do
    get regla_editar_path("precio")
    assert_response :ok
    assert_select "textarea#codigo", /reject :below-price/
    # Probar responde 200 sin redirigir, y Turbo se come esas respuestas: el formulario va sin Turbo.
    assert_select "form#form_regla[data-turbo=false]"
    post regla_guardar_path("precio"), params: { probar: "1", codigo: ReglaPrecio::DE_FABRICA, producto: "cats", cantidad: "1", precio: "30" }
    assert_select "#decision", /Se frena: por debajo/
    assert_select "p", /Toca: \$42.00/
    post regla_guardar_path("precio"), params: { probar: "1", codigo: "(if (authorized) (allow) (to-review \"x\"))", producto: "CATS", precio: "30", autorizado: "1" }
    assert_select "#decision", /Se cobra/
    post regla_guardar_path("precio"), params: { codigo: "(allow)" }
    assert_equal "(allow)", Regla.vigente("precio").codigo
    assert_nil Regla.vigente("corte")
    assert_raises(ActionController::UrlGenerationError) { regla_editar_path("nada") }
  end

  test "retiros: el editor prueba y una regla propia manda a revisión los grandes aunque haya permiso" do
    get regla_editar_path("retiro")
    assert_select "input#motivo[value=?]", "caja fuerte"
    post regla_guardar_path("retiro"), params: { probar: "1", codigo: ReglaRetiro::DE_FABRICA, monto: "100" }
    assert_select "#decision", /Se frena: hace falta permiso para retirar/
    post regla_guardar_path("retiro"), params: { codigo: '(if (> (amount) 1000) (to-review "retiro grande") (allow))' }
    post entrar_path, params: { usuario: "supervisora", password: "secreto1" }
    post caja_retirar_path, params: { monto: "200", motivo: "caja fuerte" }
    assert_equal 1, cortes(:tienda_abierto).retiros.count
    assert_equal 0, Revision.count
    Inventario.mover!(sucursal: sucursales(:tienda), producto: productos(:catsup), tipo: "entrada", cantidad: 30, usuario: usuarios(:admin))
    Caja.cobrar!(sucursal: sucursales(:tienda), usuario: usuarios(:admin), clave: "r", lineas: [ { producto_id: productos(:catsup).id, cantidad: 30 } ], pagos: [ { forma: "efectivo", monto_centavos: 126_000 } ])
    post caja_retirar_path, params: { monto: "1200", motivo: "banco" }
    assert_match "queda por revisar", flash[:notice]
    assert_equal "banco\nretiro grande", Revision.last.motivo
  end

  test "inventario: el editor prueba, y una regla que deja pasar a la cajera sin permiso no deja nada por revisar" do
    get regla_editar_path("movimiento")
    assert_select "select#tipo option[selected][value=merma]"
    post regla_guardar_path("movimiento"), params: { probar: "1", codigo: "(if (= (kind) :waste) (to-review \"merma\") (allow))", producto: "CATS", tipo: "merma" }
    assert_select "#decision", /Se mueve y queda por revisar: merma/
    post regla_guardar_path("movimiento"), params: { codigo: "(if (= (kind) :in) (allow) (reject :needs-permission))" }
    post regla_guardar_path("retiro"), params: { codigo: "(allow)" }
    post entrar_path, params: { usuario: "cajera", password: "secreto1" }
    post movimientos_inventario_path, params: { producto_id: productos(:catsup).id, tipo: "entrada", cantidad: "2", motivo: "llegó" }
    assert_redirected_to kardex_inventario_path(producto_id: productos(:catsup).id, sucursal_id: sucursales(:tienda).id)
    assert_no_match "por revisar", Movimiento.last.motivo
    post caja_retirar_path, params: { monto: "100", motivo: "caja fuerte" }
    assert_equal 1, cortes(:tienda_abierto).retiros.count
    assert_equal 0, Revision.count
  end

  test "facturas: el editor prueba con el candado de Ajustes y desaparece con el módulo de compras apagado" do
    post regla_guardar_path("factura"), params: { probar: "1", codigo: ReglaFactura::DE_FABRICA, productos_de_mas: "2", valor_de_mas: "300" }
    assert_select "#decision", /Se frena/
    assert_select "p", /candado de Ajustes › Compras está puesto/
    post regla_guardar_path("factura"), params: { probar: "1", codigo: ReglaFactura::EJEMPLO, productos_de_mas: "1", valor_de_mas: "80" }
    assert_select "#decision", /Se registra y queda por revisar: Small excess/
    get regla_editar_path("factura")
    assert_select "a[href=?]", regla_editar_path("factura")
    Modulo.guardar!(Modulo::OPCIONALES - %w[compras], comprobar: false)
    get regla_editar_path("corte")
    assert_select "a[href=?]", regla_editar_path("factura"), 0
  end

  test "cada regla guarda la versión de su contrato; una vieja se avisa y restaurarla no la disfraza de nueva" do
    vieja = Regla.create!(gancho: "corte", codigo: "(allow)", version: 0, usuario: usuarios(:admin))
    get regla_editar_path("corte")
    assert_select "#aviso_vieja", /versión 0 del gancho y Sakuya ya va en la 1/
    post regla_guardar_path("corte"), params: { codigo: "(allow)" }
    assert_equal 1, Regla.vigente("corte").version
    get regla_editar_path("corte")
    assert_select "#aviso_vieja", 0
    assert_select "span", /contrato v0/
    post regla_restaurar_path("corte", vieja)
    assert_equal 0, Regla.vigente("corte").version
    tablero = Regla.create!(gancho: "tablero", codigo: "(dashboard)", version: 0, usuario: usuarios(:admin))
    get tablero_editar_path
    assert_select "#aviso_vieja"
    assert_equal 1, Regla.create!(gancho: "tablero", codigo: tablero.codigo, usuario: usuarios(:admin)).version
  end

  test "probar con datos de verdad: el corte abierto, una venta repasada renglón por renglón y una factura registrada" do
    usuarios(:admin).update!(sucursal: sucursales(:tienda))
    tienda = sucursales(:tienda)
    Inventario.mover!(sucursal: tienda, producto: productos(:catsup), tipo: "entrada", cantidad: 5, usuario: usuarios(:admin))
    venta = Caja.cobrar!(sucursal: tienda, usuario: usuarios(:supervisora), clave: "v", autorizador: usuarios(:supervisora),
                         lineas: [ { producto_id: productos(:catsup).id, cantidad: 1 }, { producto_id: productos(:catsup).id, cantidad: 1, precio_centavos: 3_000 } ],
                         pagos: [ { forma: "efectivo", monto_centavos: 7_200 } ])
    get regla_editar_path("corte")
    assert_select "input#esperado[readonly][value='572.00']", 1, "fondo de 500 + 72 de la venta"
    post regla_guardar_path("corte"), params: { probar: "1", codigo: '(if (= (tickets) 1) (allow) (reject "no"))', contado: "572" }
    assert_select "#decision", /Se cierra/
    post regla_guardar_path("corte"), params: { probar: "1", codigo: '(if (= (tickets) 1) (allow) (reject "no"))', contado: "572", inventado: "1", esperado: "100" }
    assert_select "#decision", /Se frena: no/

    post regla_guardar_path("precio"), params: { probar: "1", codigo: ReglaPrecio::DE_FABRICA, venta: venta.folio.downcase }
    assert_select "#decision p", 2
    assert_select "#decision p", /a \$42.00 .* Se cobra/m
    assert_select "#decision p", /a \$30.00 .* Se cobra y queda por revisar.*tiene permiso/m, "la supervisora la autorizó: frenar es revisar"
    post regla_guardar_path("precio"), params: { probar: "1", codigo: ReglaPrecio::DE_FABRICA, venta: "NO-EXISTE" }
    assert_select "p", /no hay una venta NO-EXISTE/

    prov = Proveedor.create!(nombre: "Granja", dias_credito: 0)
    Compras.facturar!(proveedor: prov, sucursal: tienda, usuario: usuarios(:admin), folio: "F-9", fecha: Date.current,
                      lineas: [ { producto_id: productos(:catsup).id, cantidad: "3", precio: "30" } ])
    post regla_guardar_path("factura"), params: { probar: "1", codigo: "(if (= (excess-value) 90) (reject :over-received) (allow))", factura: "F-9" }
    assert_select "#decision", /Se frena: se factura más de lo recibido \(Cátsup 1 kg\)/
  end

  test "ventas: el editor prueba una venta inventada a una hora y una de verdad" do
    get regla_editar_path("venta")
    assert_select "textarea#codigo", /\(allow\)/
    codigo = '(if (and (>= (hour) 22) (> (quantity-of "cats") 0)) (reject "tarde") (allow))'
    post regla_guardar_path("venta"), params: { probar: "1", codigo: codigo, claves: "cats, pech", hora: "23", total: "50" }
    assert_select "#decision", /Se frena: tarde/
    post regla_guardar_path("venta"), params: { probar: "1", codigo: codigo, claves: "cats", hora: "9" }
    assert_select "#decision", /Se cobra/
    post regla_guardar_path("venta"), params: { probar: "1", codigo: "(paid-with :card)", claves: "cats" }
    assert_select "p", /paid-with recibe una forma de pago/
  end

  test "sin reglas.editar no se entra" do
    post entrar_path, params: { usuario: "cajera", password: "secreto1" }
    get regla_editar_path("corte")
    assert_response :forbidden
    post regla_guardar_path("corte"), params: { codigo: "(allow)" }
    assert_equal 0, Regla.count
  end
end
