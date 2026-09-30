require "test_helper"

class InstalacionTest < ActionDispatch::IntegrationTest
  test "sin ningún usuario activo todo manda a instalar, y ahí se crea el administrador y entra" do
    Usuario.update_all(activo: false)
    get root_path
    assert_redirected_to instalar_path
    get entrar_path
    assert_redirected_to instalar_path

    get instalar_path
    assert_response :success
    assert_select "html[data-theme=claro]", true, "arranca en modo claro"
    assert_select "section[data-pasos-target=paso]", 7, "va por pasos"
    assert_select "section:first-of-type a[href=?]", instalar_path(idioma: "de"), true, "el idioma es el primer paso"
    assert_select "input[name='instalacion[usuario]'][value=admin]"
    get instalar_path(idioma: "de")
    assert_select "html[lang=de]", true, "el idioma se cambia desde la pantalla"
    get instalar_path
    assert_select "html[lang=de]", true, "y se recuerda"

    post instalar_path, params: { instalacion: { negocio: "Tienda Aurora", giro: "tienda", sucursal: "Planta", codigo: "pl1", nombre: "Doña Rosa", usuario: "Rosa", password: "secreto123", idioma: "es", tema: "oscuro", letra: "grande", folios_modo: "unico", folios_letra: "sucursal" } }
    assert_redirected_to root_path
    rosa = Usuario.find_by!(usuario: "rosa")
    assert_equal "Doña Rosa", rosa.nombre
    assert rosa.puede?("admin.usuarios"), "el primer usuario es administrador"
    assert_equal "PL1", rosa.sucursal.codigo
    assert_equal "PL1-00001", Folio.siguiente!(rosa.sucursal, "venta"), "numeración única con el código de la sucursal delante"
    assert rosa.sucursal.matriz?
    assert_equal "Tienda Aurora", Ajuste["negocio.nombre"]
    assert_equal "es", rosa.idioma
    assert_equal %w[oscuro grande normal], [ rosa.tema, rosa.letra, rosa.densidad ], "la apariencia elegida se queda en el usuario"
    assert_equal %w[compras conteos], Modulo.activos, "el giro deja encendido solo lo suyo"

    follow_redirect!
    assert_response :success, "queda con la sesión iniciada"
    assert_select "html[lang=es]"
  end

  test "con usuarios la pantalla de instalar ya no existe" do
    get instalar_path
    assert_redirected_to root_path
    post instalar_path, params: { instalacion: { nombre: "X", usuario: "x", password: "secreto123" } }
    assert_redirected_to root_path
    assert_nil Usuario.find_by(usuario: "x")
  end

  test "con datos malos lo dice y no deja nada a medias" do
    Usuario.update_all(activo: false)
    post instalar_path, params: { instalacion: { negocio: "X", giro: "tienda", sucursal: "Planta", codigo: "PL1", nombre: "", usuario: "rosa", password: "secreto123" } }
    assert_response :unprocessable_entity
    assert_nil Usuario.find_by(usuario: "rosa")
    assert_nil Sucursal.find_by(codigo: "PL1"), "la transacción se deshace entera"
  end
end
