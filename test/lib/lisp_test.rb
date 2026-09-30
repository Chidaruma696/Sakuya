require "test_helper"

class LispTest < ActiveSupport::TestCase
  def ev(texto, **opciones) = Lisp.ejecutar(texto, **opciones)

  test "lee números, cadenas, palabras clave, símbolos, comentarios y citas" do
    formas = Lisp::Lector.leer(%( 42 -7 2.50 "a \\"b\\"\\n" :money foo ; nada\n 'x true false nil ))
    assert_equal [ 42, -7, BigDecimal("2.50"), "a \"b\"\n", :money, Lisp::Simbolo.new("foo"),
                   [ Lisp::Simbolo.new("quote"), Lisp::Simbolo.new("x") ], true, false, nil ], formas
    assert_equal [ [ Lisp::Simbolo.new("quote"), [ 1, 2 ] ] ], Lisp::Lector.leer("'(1 2)")
  end

  test "lo que no se puede leer lo dice con la línea" do
    assert_match "falta cerrar 1", assert_raises(Lisp::ErrorDeLectura) { ev("(+ 1 2") }.message
    assert_match "sobra un ) en la línea 2", assert_raises(Lisp::ErrorDeLectura) { ev("1\n)") }.message
    assert_match "cadena sin cerrar", assert_raises(Lisp::ErrorDeLectura) { ev(%((str "hola))) }.message
    assert_match "anidados", assert_raises(Lisp::ErrorDeLectura) { ev("(" * 70 + ")" * 70) }.message
    assert_raises(Lisp::ErrorDeLectura) { ev("1" * (Lisp::LARGO_MAXIMO + 1)) }
  end

  test "el dinero es decimal exacto, nunca flotante" do
    assert_equal BigDecimal("0.3"), ev("(+ 0.1 0.2)")
    assert_equal 6, ev("(* 1 2 3)")
    assert_equal BigDecimal("33.33"), ev("(round (/ 100 3) 2)")
    assert_equal 3, ev("(round 2.5)")
    assert_equal(-5, ev("(- 5)"))
    assert_match "entre cero", assert_raises(Lisp::Error) { ev("(/ 1 0)") }.message
    assert_match "espera números", assert_raises(Lisp::Error) { ev(%((+ 1 "2"))) }.message
  end

  test "formas especiales: if, cond, when, and, or, let, define, lambda" do
    assert_equal "sí", ev(%((if (> 3 2) "sí" "no")))
    assert_nil ev("(if false 1)")
    assert_equal :medio, ev("(let ((x 5)) (cond ((< x 3) :poco) ((< x 10) :medio) (else :mucho)))")
    assert_nil ev("(when false 1)")
    assert_equal 2, ev("(unless false 1 2)")
    assert_equal 3, ev("(and 1 2 3)")
    assert_equal false, ev("(and 1 false 3)")
    assert_equal 2, ev("(or nil 2)")
    assert_equal 120, ev("(define (fact n) (if (<= n 1) 1 (* n (fact (- n 1))))) (fact 5)")
    assert_equal [ 2, 4, 6 ], ev("(map (fn (x) (* x 2)) '(1 2 3))")
    assert_equal [ 3 ], ev("(filter (lambda (x) (> x 2)) (list 1 2 3))")
    assert_equal 6, ev("(reduce + 0 '(1 2 3))")
    assert_equal 10, ev("(define base 7) (define (mas3 x) (+ x 3)) (mas3 base)")
  end

  test "listas, mapas y cadenas" do
    assert_equal 1, ev("(first '(1 2))")
    assert_equal [ 2 ], ev("(rest '(1 2))")
    assert_equal [ 0, 1, 2 ], ev("(cons 0 '(1 2))")
    assert_equal 3, ev("(count '(a b c))")
    assert_equal true, ev("(empty? '())")
    assert_equal BigDecimal("6.5"), ev("(sum '(1 2 3.5))")
    assert_equal "Total: 6.5 :money", ev(%((str "Total: " (sum '(1 2 3.5)) " " :money)))
    assert_equal 9, ev("(get (datos) :precio)", funciones: { "datos" => -> { { precio: 9 } } })
  end

  test "solo existe lo que Sakuya registra: nada de Ruby ni del sistema" do
    assert_match "no conozco «system»", assert_raises(Lisp::Error) { ev(%((system "ls"))) }.message
    assert_raises(Lisp::Error) { ev(%((File.read "/etc/passwd"))) }
    assert_raises(Lisp::Error) { ev(%(("upcase" "hola"))) }
    assert_equal 12, ev("(ventas)", funciones: { "ventas" => -> { 12 } })
    assert_match "recibe 0 y le diste 1", assert_raises(Lisp::Error) { ev("(ventas 1)", funciones: { "ventas" => -> { 12 } }) }.message
  end

  test "un ciclo o una recursión sin fin se cortan" do
    assert_raises(Lisp::Agotado) { ev("(define (f x) (f x)) (f 1)") }
    assert_raises(Lisp::Agotado) { ev("(define (g n) (+ 1 (g n))) (g 1)", pasos: 1_000_000) }
    assert_equal 100, ev("(define (h n) (if (= n 0) 0 (+ 1 (h (- n 1))))) (h 100)", profundidad: 150)
  end

  test "define no toca las funciones base de otros programas" do
    ev("(define (+ a b) 0)")
    assert_equal 3, ev("(+ 1 2)")
  end

  test "a_texto escribe los valores como en el programa" do
    assert_equal %((1 "a" :b 2.5 nil true)), Lisp.a_texto(ev(%((list 1 "a" :b 2.5 nil true))))
  end
end
