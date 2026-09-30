require "test_helper"

class TableroControllerTest < ActionDispatch::IntegrationTest
  setup { post entrar_path, params: { usuario: "admin", password: "secreto1" } }

  test "inicio pinta el programa guardado, y el editor prueba, guarda y restaura" do
    get root_path
    assert_select ".etiqueta-dato", 8
    assert_select "a[href=?]", tablero_editar_path

    get tablero_editar_path
    assert_response :ok
    assert_select "textarea#codigo", /\(tile :sales\)/

    post tablero_probar_path, params: { codigo: %((dashboard (tile "Solo esta" 7))) }
    assert_response :ok
    assert_select ".etiqueta-dato", /Solo esta/
    assert_equal 0, Regla.count, "probar no guarda"

    post tablero_guardar_path, params: { codigo: "(dashboard (tile :sales" }
    assert_response :unprocessable_entity
    assert_select "p", /falta cerrar/
    assert_equal 0, Regla.count

    post tablero_guardar_path, params: { codigo: %((dashboard (tile "Solo esta" 7))) }
    assert_redirected_to root_path
    get root_path
    assert_select ".etiqueta-dato", 1
    assert_select ".etiqueta-dato", /Solo esta/

    primera = Regla.first
    post tablero_guardar_path, params: { codigo: "(dashboard (tile :tickets))" }
    post tablero_restaurar_path(primera)
    assert_redirected_to tablero_editar_path
    assert_equal primera.codigo, Regla.vigente("tablero").codigo
    assert_equal 3, Regla.count, "restaurar asienta otra versión, no borra"
  end

  test "un programa que truena en Inicio no tumba la página: sale el de fábrica con aviso" do
    Regla.create!(gancho: "tablero", codigo: "(dashboard (tile :nada))", usuario: usuarios(:admin))
    get root_path
    assert_response :ok
    assert_select ".etiqueta-dato", 8
    assert_select "div", /tiene un error/
  end

  test "el editor vive en Ajustes, en las opciones avanzadas" do
    get ajustes_path
    assert_select "nav li", /Opciones avanzadas/
    assert_select "nav a[href=?]", tablero_editar_path
    get tablero_editar_path
    assert_select "nav a[href=?][class*=font-semibold]", tablero_editar_path
    assert_match %r{/ajustes/avanzado/tablero}, tablero_editar_path
  end

  test "sin reglas.editar no se entra al editor ni se ve el botón" do
    delete salir_path
    post entrar_path, params: { usuario: "supervisora", password: "secreto1" }
    get root_path
    assert_select "a[href=?]", tablero_editar_path, count: 0
    get ajustes_path
    assert_select "nav li", { text: /Opciones avanzadas/, count: 0 }
    get tablero_editar_path
    assert_response :forbidden
    post tablero_guardar_path, params: { codigo: "(dashboard)" }
    assert_response :forbidden
  end
end
