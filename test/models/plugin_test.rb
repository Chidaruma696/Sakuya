require "test_helper"

class PluginTest < ActiveSupport::TestCase
  def instalar(texto = Plugin::EJEMPLO) = Plugin.instalar!(texto, usuario: usuarios(:admin))

  test "lee la cabecera, las funciones, los informes y las traducciones del ejemplo" do
    leido = Plugin.leer(Plugin::EJEMPLO)
    assert_equal "fonda", leido.identificador
    assert_equal "Fonda", leido.datos["name"]
    assert_equal 1, leido.funciones.size
    assert_equal [ "Sales of the week", "(sum-of :total (sales (days-ago 7) (today)))" ], [ leido.informes.first.titulo, leido.informes.first.codigo ]
    assert_equal({ "caja.cobrar" => "Encaisser", "cinta.pestanas.caja" => "Caisse" }, leido.traducciones.first.textos)
  end

  test "rechaza lo que un plugin no puede traer" do
    assert_match "empezar con (plugin", assert_raises(Lisp::Error) { Plugin.leer("(define (x) 1)") }.message
    assert_match "no sirve", assert_raises(Lisp::Error) { Plugin.leer('(plugin "Mal Nombre")') }.message
    assert_match "solo declara", assert_raises(Lisp::Error) { Plugin.leer(%((plugin "uno") (+ 1 2))) }.message
    assert_match "prefijo del plugin: uno/", assert_raises(Lisp::Error) { Plugin.leer(%((plugin "uno") (define (sales) 0))) }.message
    assert_match "(report", assert_raises(Lisp::Error) { Plugin.leer(%((plugin "uno") (report 1 2))) }.message
    assert_match "clave", assert_raises(Lisp::Error) { Plugin.leer(%((plugin "uno") (translation "fr" "Français" ("solo")))) }.message
    assert_match "falta cerrar", assert_raises(Lisp::Error) { Plugin.leer('(plugin "uno"') }.message
  end

  test "sus funciones se usan en las reglas y el REPL solo encendido, y lo de fábrica no depende de ellas" do
    plugin = instalar(%((plugin "fonda") (define (fonda/doble x) (* 2 x)) (define fonda/tope 300)))
    assert_not plugin.activo, "llega apagado"
    assert_raises(Lisp::Error) { Repl.evaluar("(fonda/doble 2)", sucursales: [ sucursales(:tienda) ]) }
    plugin.update!(activo: true)
    assert_equal 4, Repl.evaluar("(fonda/doble 2)", sucursales: [ sucursales(:tienda) ])
    datos = ReglaCorte::Datos.new(Corte.new(fondo_centavos: 50_000), 0, autorizado: false)
    assert ReglaCorte.evaluar("(if (> (fonda/doble (abs (difference))) fonda/tope) (to-review \"x\") (allow))", datos).revisar?
    plugin.update!(codigo: %((plugin "fonda") (define (fonda/doble x) (/ x 0))))
    d = ReglaCorte.decidir(cortes(:tienda_abierto), contado_centavos: 50_000, usuario: usuarios(:cajera), codigo: "(if (fonda/doble 1) (allow) (allow))")
    assert d.permite?, "decidió la de fábrica sin el plugin"
    assert_match "dividir entre cero", d.error
  end

  test "subir el mismo identificador lo pone al día y conserva si estaba encendido" do
    instalar.update!(activo: true)
    plugin = instalar(Plugin::EJEMPLO.sub(%((version "1.0")), %((version "1.1"))))
    assert_equal [ 1, "1.1", true ], [ Plugin.count, plugin.version, plugin.activo ]
  end
end
