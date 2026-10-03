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

  test "sin reglas.editar no se entra" do
    post entrar_path, params: { usuario: "cajera", password: "secreto1" }
    get regla_editar_path("corte")
    assert_response :forbidden
    post regla_guardar_path("corte"), params: { codigo: "(allow)" }
    assert_equal 0, Regla.count
  end
end
