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

    post tablero_guardar_path, params: { probar: "1", codigo: %((dashboard (tile "Solo esta" 7))) }
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

  test "probar desde el modal devuelve solo la vista previa, o el error" do
    post tablero_guardar_path, params: { probar: "1", codigo: %((dashboard (tile "En el modal" 3))) }, xhr: true
    assert_response :ok
    assert_no_match "<html", response.body
    assert_select ".etiqueta-dato", /En el modal/
    post tablero_guardar_path, params: { probar: "1", codigo: "(dashboard (tile :sales" }, xhr: true
    assert_response :unprocessable_entity
    assert_match "falta cerrar", response.body
    assert_select ".etiqueta-dato", 0
    assert_equal 0, Regla.count
    get tablero_editar_path
    assert_select "dialog[data-vista-previa-target=dialogo]"
    assert_select "button[data-action='vista-previa#probar']"
  end

  test "con datos de prueba la vista previa sale llena, avisa que son inventados y no guarda nada" do
    post tablero_guardar_path, params: { probar: "1", muestra: "1", codigo: %((dashboard (tile :sales) (tile "Pechuga" (sold "PECH")) (panel :top-products) (panel :closed-cash-counts))) }, xhr: true
    assert_response :ok
    assert_match "Datos de prueba inventados", response.body
    assert_select ".valor-dato", /\$18,450\.50/
    assert_select "td", /Pechuga de pollo/
    assert_select "td", /C-00041/
    post tablero_guardar_path, params: { probar: "1", muestra: "1", codigo: %((dashboard (tile "x" (sold "NADA")))) }, xhr: true
    assert_response :unprocessable_entity
    assert_match "no hay producto con clave NADA", response.body
    assert_equal 0, Regla.count
    assert_equal 0, Venta.count, "la muestra no toca la base"
    get tablero_editar_path
    assert_select "input[type=checkbox][name=muestra]"
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

  # Los tests corren sin protección CSRF; esta la enciende para probar lo que hace el navegador:
  # el formulario trae un token atado a su dirección y el modal manda además el de la página.
  test "probar y guardar pasan la protección CSRF, desde el modal y sin JavaScript" do
    ActionController::Base.allow_forgery_protection = true
    get tablero_editar_path
    token_formulario = css_select("form#form_tablero input[name=authenticity_token]").first["value"]
    token_pagina = css_select("meta[name=csrf-token]").first["content"]

    post tablero_guardar_path, params: { authenticity_token: token_formulario, probar: "1", codigo: "(dashboard (tile :tickets))" },
                               headers: { "X-CSRF-Token" => token_pagina }, xhr: true
    assert_response :ok
    post tablero_guardar_path, params: { authenticity_token: token_formulario, probar: "1", codigo: "(dashboard (tile :tickets))" }
    assert_response :ok
    assert_equal 0, Regla.count
    post tablero_guardar_path, params: { authenticity_token: token_formulario, codigo: "(dashboard (tile :tickets))" }
    assert_redirected_to root_path
    assert_equal 1, Regla.count
  ensure
    ActionController::Base.allow_forgery_protection = false
  end
end
