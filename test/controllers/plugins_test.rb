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

  test "sin reglas.editar no se entra" do
    post entrar_path, params: { usuario: "cajera", password: "secreto1" }
    get plugins_path
    assert_response :forbidden
  end
end
