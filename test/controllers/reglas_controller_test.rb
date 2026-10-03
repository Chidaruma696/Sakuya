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

  test "sin reglas.editar no se entra" do
    post entrar_path, params: { usuario: "cajera", password: "secreto1" }
    get regla_editar_path("corte")
    assert_response :forbidden
    post regla_guardar_path("corte"), params: { codigo: "(allow)" }
    assert_equal 0, Regla.count
  end
end
