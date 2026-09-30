# El Lisp de Sakuya: un dialecto chico, escrito aquí, para las reglas de cada negocio.
#
# Solo sabe hacer lo que Sakuya le registra: no hay archivos, ni red, ni procesos, ni acceso a
# Ruby. Cada evaluación lleva un contador de pasos y un límite de profundidad, así que un bucle
# o una recursión sin fin se cortan con un error en vez de congelar la caja. El dinero va en
# BigDecimal, nunca en flotante. Los nombres del lenguaje van en inglés, como en Emacs.
#
#   Lisp.ejecutar("(+ 1 2.50)")                    # => 0.35e1
#   Lisp.ejecutar("(total)", funciones: { "total" => -> { 10 } })
module Lisp
  class Error < StandardError; end
  # El texto no se puede leer: paréntesis sin cerrar, una cadena sin comillas de cierre…
  class ErrorDeLectura < Error; end
  # Se acabaron los pasos o la profundidad.
  class Agotado < Error; end

  LARGO_MAXIMO = 20_000

  # Un símbolo del programa (un nombre), distinto de una cadena y de una palabra clave (:x).
  Simbolo = Data.define(:nombre) do
    def to_s = nombre
  end

  # Una función escrita en el programa: (lambda (x) …) o (define (f x) …).
  Procedimiento = Data.define(:parametros, :cuerpo, :entorno, :nombre)

  # Una función de Sakuya, escrita en Ruby. `aridad` es un Range; `bloque` recibe los argumentos
  # ya evaluados y, si lo pide, el evaluador (para las que llaman a otras funciones, como map).
  Nativa = Data.define(:nombre, :aridad, :bloque, :con_evaluador)

  # Lee y evalúa todo el texto; devuelve el valor de la última expresión.
  def self.ejecutar(texto, funciones: {}, pasos: 10_000, profundidad: 100)
    entorno = Entorno.new(Base.entorno)
    funciones.each { |nombre, f| entorno.definir(nombre.to_s, f.is_a?(Nativa) ? f : Base.nativa(nombre.to_s, f)) }
    evaluador = Evaluador.new(pasos: pasos, profundidad: profundidad)
    Lector.leer(texto).reduce(nil) { |_, forma| evaluador.evaluar(forma, entorno) }
  end

  # El valor escrito como se escribiría en el programa, para mensajes y para el REPL.
  def self.a_texto(valor)
    case valor
    when nil then "nil"
    when true then "true"
    when false then "false"
    when Simbolo then valor.nombre
    when Symbol then ":#{valor}"
    when String then valor.inspect
    when BigDecimal then valor.to_s("F")
    when Array then "(#{valor.map { |v| a_texto(v) }.join(" ")})"
    when Hash then "{#{valor.map { |k, v| "#{a_texto(k)} #{a_texto(v)}" }.join(" ")}}"
    when Procedimiento then "#<fn #{valor.nombre || "anónima"}>"
    when Nativa then "#<fn #{valor.nombre}>"
    else valor.to_s
    end
  end
end
