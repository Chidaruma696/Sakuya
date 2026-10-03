require "test_helper"

class PluginsTest < ActionDispatch::IntegrationTest
  setup { post entrar_path, params: { usuario: "admin", password: "secreto1" } }

  def subir(texto)
    post plugins_path, params: { archivo: Rack::Test::UploadedFile.new(StringIO.new(texto.dup), "text/plain", original_filename: "p.lisp") }
  end

  test "se sube, se ve qué trae, se enciende, se apaga y se quita" do
    get plugins_path
    assert_match "Todavía no hay plugins", response.body
    subir(Plugin::EJEMPLO)
    assert_match "Llega apagado", flash[:notice]
    get plugins_path
    assert_select "#plugin_fonda", /1 función.*1 informe.*1 idioma/m
    plugin = Plugin.last
    post alternar_plugin_path(plugin)
    assert plugin.reload.activo
    post alternar_plugin_path(plugin)
    assert_not plugin.reload.activo
    delete plugin_path(plugin)
    assert_equal 0, Plugin.count
    subir("(define (x) 1)")
    assert_match "No se instaló", flash[:alert]
  end

  test "los informes de un plugin encendido salen como botones en el REPL" do
    Plugin.instalar!(%((plugin "fonda") (report "Cuántos productos" (count (products)))), usuario: usuarios(:admin))
    get repl_path
    assert_select "#informes", 0, "apagado no aporta nada"
    Plugin.last.update!(activo: true)
    get repl_path
    assert_select "#informes button", "Cuántos productos"
    post repl_evaluar_path, params: { texto: "(count (products))" }
    assert_select "#resultado pre", Producto.count.to_s
  end

  test "un plugin trae un idioma: se elige en Para ti, lo que no traduce sale en español y al apagarlo se vuelve a lo de fábrica" do
    plugin = Plugin.instalar!(Plugin::EJEMPLO, usuario: usuarios(:admin))
    get ajustes_seccion_path("para_ti")
    assert_no_match "Français", response.body
    plugin.update!(activo: true)
    get ajustes_seccion_path("para_ti")
    assert_match "Français", response.body
    patch ajustes_preferencias_path, params: { usuario: { idioma: "fr" } }
    assert_equal "fr", usuarios(:admin).reload.idioma
    usuarios(:admin).update!(sucursal: sucursales(:tienda))
    get caja_path
    assert_select "nav a", "Caisse"
    assert_select "button", "Encaisser"
    assert_select "button", "Vaciar ticket", "lo que el plugin no traduce cae al español"
    assert_match '"pos":', response.body, "los textos del JavaScript llegan completos"
    plugin.update!(activo: false)
    get caja_path
    assert_response :ok
    assert_select "html[lang=fr]", 0, "el usuario tenía francés; sin el plugin cae a un idioma de fábrica"
    assert_select "nav a", { text: "Caisse", count: 0 }
  end

  test "una traducción con claves que no existen no se instala" do
    texto = %((plugin "mal") (translation "fr" "Français" ("caja.no_existe" "x")))
    assert_match "no existen estas claves de texto: caja.no_existe", assert_raises(Lisp::Error) { Plugin.leer(texto) }.message
    html = %((plugin "mal") (translation "es" "Español" ("caja.excede_limite_html" "<script>")))
    assert_match "llevan HTML", assert_raises(Lisp::Error) { Plugin.leer(html) }.message
  end

  test "un plugin puede cambiar un texto de un idioma que ya existe" do
    Plugin.instalar!(%((plugin "turnos") (translation "es" "Español" ("caja.cobrar" "Cobrar ya"))), usuario: usuarios(:admin)).update!(activo: true)
    post entrar_path, params: { usuario: "cajera", password: "secreto1" }
    get caja_path
    assert_select "button", "Cobrar ya"
  end

  test "sin reglas.editar no se entra" do
    post entrar_path, params: { usuario: "cajera", password: "secreto1" }
    get plugins_path
    assert_response :forbidden
  end
end
