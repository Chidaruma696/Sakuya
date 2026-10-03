require "test_helper"

class ReglaCorteControllerTest < ActionDispatch::IntegrationTest
  setup { post entrar_path, params: { usuario: "admin", password: "secreto1" } }

  test "el editor prueba con un caso, guarda solo lo que decide y restaura" do
    get ajustes_path
    assert_select "a[href=?]", regla_corte_editar_path
    get regla_corte_editar_path
    assert_response :ok
    assert_select "textarea#codigo", /reject :over-limit/
    assert_select "input#esperado[value='500.00']", 1, "de entrada, lo que espera el corte abierto"

    codigo = '(if (< (difference) 0) (reject "falta") (allow))'
    post regla_corte_guardar_path, params: { probar: "1", codigo: codigo, esperado: "500", contado: "480" }
    assert_response :ok
    assert_select "#decision", /Se frena: falta/
    assert_equal 0, Regla.count, "probar no guarda"

    post regla_corte_guardar_path, params: { codigo: "(allow" }
    assert_response :unprocessable_entity
    assert_select "p", /falta cerrar/
    post regla_corte_guardar_path, params: { codigo: "(+ 1 2)" }
    assert_response :unprocessable_entity
    assert_select "p", /terminó en 3/
    assert_equal 0, Regla.count

    post regla_corte_guardar_path, params: { codigo: codigo }
    assert_redirected_to regla_corte_editar_path
    assert_equal codigo, Regla.vigente("corte").codigo
    primera = Regla.vigente("corte")
    post regla_corte_guardar_path, params: { codigo: "(allow)" }
    post regla_corte_restaurar_path(primera)
    assert_equal codigo, Regla.vigente("corte").codigo
    assert_equal 3, Regla.count
    assert_equal 0, Regla.de("tablero").count, "cada gancho lleva sus versiones"
  end

  test "sin reglas.editar no se entra" do
    post entrar_path, params: { usuario: "cajera", password: "secreto1" }
    get regla_corte_editar_path
    assert_response :forbidden
    post regla_corte_guardar_path, params: { codigo: "(allow)" }
    assert_equal 0, Regla.count
  end
end
