module Lisp
  # Las funciones que todo programa tiene: números, comparaciones, listas y cadenas. Nada de aquí
  # toca la base ni el mundo de afuera; eso lo registra cada gancho con sus propias funciones.
  module Base
    DECIMALES_DIVISION = 20

    def self.entorno
      @entorno ||= Entorno.new.tap do |e|
        FUNCIONES.each { |nombre, (aridad, bloque, con_evaluador)| e.definir(nombre, Nativa.new(nombre: nombre, aridad: aridad, bloque: bloque, con_evaluador: !!con_evaluador)) }
      end.congelar!
    end

    # Envuelve un bloque de Ruby como función del lenguaje; la aridad sale del bloque.
    def self.nativa(nombre, bloque)
      aridad = bloque.arity.negative? ? ((bloque.arity.abs - 1)..) : (bloque.arity..bloque.arity)
      Nativa.new(nombre: nombre, aridad: aridad, bloque: bloque, con_evaluador: false)
    end

    def self.numero!(x, quien)
      raise Error, "#{quien} espera números y recibió #{Lisp.a_texto(x)}" unless x.is_a?(Numeric)
      x
    end

    def self.lista!(x, quien)
      return [] if x.nil?
      raise Error, "#{quien} espera una lista y recibió #{Lisp.a_texto(x)}" unless x.is_a?(Array)
      x
    end

    def self.dividir(a, b)
      raise Error, "no se puede dividir entre cero" if b.zero?
      BigDecimal(a.to_s).div(BigDecimal(b.to_s), DECIMALES_DIVISION)
    end

    def self.comparar(nombre, args, &prueba)
      args.each { |x| numero!(x, nombre) }
      args.each_cons(2).all? { |a, b| prueba.call(a, b) }
    end

    def self.verdad?(x) = !(x.nil? || x == false)

    FUNCIONES = {
      "+" => [ 0.., ->(*xs) { xs.each { |x| numero!(x, "+") }.sum(0) } ],
      "-" => [ 1.., ->(x, *xs) { numero!(x, "-"); xs.empty? ? -x : xs.reduce(x) { |a, b| a - numero!(b, "-") } } ],
      "*" => [ 0.., ->(*xs) { xs.reduce(1) { |a, b| a * numero!(b, "*") } } ],
      "/" => [ 2.., ->(x, *xs) { xs.reduce(numero!(x, "/")) { |a, b| dividir(a, numero!(b, "/")) } } ],
      "round" => [ 1..2, ->(x, d = 0) { numero!(x, "round"); BigDecimal(x.to_s).round(d, :half_up).then { |r| d.zero? ? r.to_i : r } } ],
      "abs" => [ 1..1, ->(x) { numero!(x, "abs").abs } ],
      "min" => [ 1.., ->(*xs) { xs.each { |x| numero!(x, "min") }.min } ],
      "max" => [ 1.., ->(*xs) { xs.each { |x| numero!(x, "max") }.max } ],
      "=" => [ 1.., ->(*xs) { xs.each_cons(2).all? { |a, b| a == b } } ],
      "/=" => [ 2..2, ->(a, b) { a != b } ],
      "<" => [ 1.., ->(*xs) { comparar("<", xs) { |a, b| a < b } } ],
      ">" => [ 1.., ->(*xs) { comparar(">", xs) { |a, b| a > b } } ],
      "<=" => [ 1.., ->(*xs) { comparar("<=", xs) { |a, b| a <= b } } ],
      ">=" => [ 1.., ->(*xs) { comparar(">=", xs) { |a, b| a >= b } } ],
      "not" => [ 1..1, ->(x) { !verdad?(x) } ],
      "list" => [ 0.., ->(*xs) { xs } ],
      "first" => [ 1..1, ->(l) { lista!(l, "first").first } ],
      "rest" => [ 1..1, ->(l) { lista!(l, "rest").drop(1) } ],
      "nth" => [ 2..2, ->(l, i) { lista!(l, "nth")[numero!(i, "nth").to_i] } ],
      "count" => [ 1..1, ->(l) { l.is_a?(String) ? l.length : lista!(l, "count").size } ],
      "empty?" => [ 1..1, ->(l) { lista!(l, "empty?").empty? } ],
      "cons" => [ 2..2, ->(x, l) { [ x, *lista!(l, "cons") ] } ],
      "append" => [ 0.., ->(*ls) { ls.flat_map { |l| lista!(l, "append") } } ],
      "reverse" => [ 1..1, ->(l) { lista!(l, "reverse").reverse } ],
      "take" => [ 2..2, ->(n, l) { lista!(l, "take").first(numero!(n, "take").to_i) } ],
      "sum" => [ 1..1, ->(l) { lista!(l, "sum").each { |x| numero!(x, "sum") }.sum(0) } ],
      "map" => [ 2..2, ->(ev, f, l) { lista!(l, "map").map { |x| ev.aplicar(f, [ x ]) } }, true ],
      "filter" => [ 2..2, ->(ev, f, l) { lista!(l, "filter").select { |x| verdad?(ev.aplicar(f, [ x ])) } }, true ],
      "reduce" => [ 3..3, ->(ev, f, inicial, l) { lista!(l, "reduce").reduce(inicial) { |a, x| ev.aplicar(f, [ a, x ]) } }, true ],
      "get" => [ 2..3, ->(m, k, otro = nil) { m.is_a?(Hash) ? m.fetch(k, otro) : raise(Error, "get espera un mapa") } ],
      "str" => [ 0.., ->(*xs) { xs.map { |x| x.is_a?(String) ? x : Lisp.a_texto(x) }.join } ],
      "number?" => [ 1..1, ->(x) { x.is_a?(Numeric) } ],
      "string?" => [ 1..1, ->(x) { x.is_a?(String) } ],
      "list?" => [ 1..1, ->(x) { x.is_a?(Array) } ],
      "nil?" => [ 1..1, ->(x) { x.nil? } ]
    }.freeze
  end
end
