require "test_helper"

class ModulosTest < ActionDispatch::IntegrationTest
  setup { post entrar_path, params: { usuario: "admin", password: "secreto1" } }

  test "de fábrica todo está encendido y se ve en la cinta" do
    get root_path
    assert_select "aside[data-lateral-target=panel] div", /Compras/
    assert_select "aside[data-lateral-target=panel] div", /Conteos/
  end

  test "apagar compras la quita de la cinta, de los roles y sus pantallas lo dicen" do
    patch ajustes_sistema_path, params: { modulos: [ "almacenes", "conteos" ] }
    assert_redirected_to ajustes_seccion_path("modulos")
    assert_not Modulo.activo?("compras")
    assert Modulo.activo?("conteos")

    get root_path
    assert_select "aside[data-lateral-target=panel] div", { text: /Compras/, count: 0 }
    get proveedores_path
    assert_response :not_found
    assert_select "h1", /Compras/
    get new_admin_rol_path
    assert_select "input[value='compras.recibir']", count: 0
    assert_select "input[value='caja.vender']"
  end

  test "una tienda arranca con compras y conteos; los módulos se encienden y apagan desde Ajustes" do
    Modulo.aplicar_giro!("tienda")
    assert_equal %w[compras conteos], Modulo.activos
    get root_path
    assert_select "aside[data-lateral-target=panel] div", { text: /Almacenes/, count: 0 }
    patch ajustes_sistema_path, params: { modulos: %w[compras almacenes conteos], volver: "modulos" }
    Current.modulos = nil
    assert_equal %w[compras almacenes conteos], Modulo.activos
    get ajustes_seccion_path("modulos")
    assert_select "input[data-modulo=almacenes]"
  end

  test "no se apaga un módulo con trabajo abierto" do
    Conteo.abrir!(sucursal: sucursales(:tienda), usuario: usuarios(:admin), responsable: usuarios(:cajera))
    e = assert_raises(ArgumentError) { Modulo.guardar!(%w[compras almacenes]) }
    assert_match "Conteos", e.message
    assert Modulo.activo?("conteos")
    Modulo.guardar!(%w[compras almacenes], comprobar: false)
    assert_not Modulo.activo?("conteos"), "sin comprobar se apaga aunque haya trabajo"
  end
end
