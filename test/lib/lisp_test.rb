require "test_helper"

class LispTest < ActiveSupport::TestCase
  def ev(text, **options) = Lisp.run(text, **options)

  test "reads numbers, strings, keywords, symbols, comments and quotes" do
    forms = Lisp::Reader.read(%( 42 -7 2.50 "a \\"b\\"\\n" :money foo ; nothing\n 'x true false nil ))
    assert_equal [ 42, -7, BigDecimal("2.50"), "a \"b\"\n", :money, Lisp::Sym.new("foo"),
                   [ Lisp::Sym.new("quote"), Lisp::Sym.new("x") ], true, false, nil ], forms
    assert_equal [ [ Lisp::Sym.new("quote"), [ 1, 2 ] ] ], Lisp::Reader.read("'(1 2)")
  end

  test "what cannot be read is reported with the line" do
    assert_match "missing 1 closing parenthesis", assert_raises(Lisp::ReadError) { ev("(+ 1 2") }.message
    assert_match "one ) too many on line 2", assert_raises(Lisp::ReadError) { ev("1\n)") }.message
    assert_match "an unclosed string", assert_raises(Lisp::ReadError) { ev(%((str "hello))) }.message
    assert_match "too many nested parentheses", assert_raises(Lisp::ReadError) { ev("(" * 70 + ")" * 70) }.message
    assert_raises(Lisp::ReadError) { ev("1" * (Lisp::MAX_LENGTH + 1)) }
  end

  test "money is exact decimal, never floating point" do
    assert_equal BigDecimal("0.3"), ev("(+ 0.1 0.2)")
    assert_equal 6, ev("(* 1 2 3)")
    assert_equal BigDecimal("33.33"), ev("(round (/ 100 3) 2)")
    assert_equal 3, ev("(round 2.5)")
    assert_equal(-5, ev("(- 5)"))
    assert_match "cannot divide by zero", assert_raises(Lisp::Error) { ev("(/ 1 0)") }.message
    assert_match "expects numbers", assert_raises(Lisp::Error) { ev(%((+ 1 "2"))) }.message
  end

  test "special forms: if, cond, when, and, or, let, define, lambda" do
    assert_equal "yes", ev(%((if (> 3 2) "yes" "no")))
    assert_nil ev("(if false 1)")
    assert_equal :middle, ev("(let ((x 5)) (cond ((< x 3) :little) ((< x 10) :middle) (else :a-lot)))")
    assert_nil ev("(when false 1)")
    assert_equal 2, ev("(unless false 1 2)")
    assert_equal 3, ev("(and 1 2 3)")
    assert_equal false, ev("(and 1 false 3)")
    assert_equal 2, ev("(or nil 2)")
    assert_equal 120, ev("(define (fact n) (if (<= n 1) 1 (* n (fact (- n 1))))) (fact 5)")
    assert_equal [ 2, 4, 6 ], ev("(map (fn (x) (* x 2)) '(1 2 3))")
    assert_equal [ 3 ], ev("(filter (lambda (x) (> x 2)) (list 1 2 3))")
    assert_equal 6, ev("(reduce + 0 '(1 2 3))")
    assert_equal 10, ev("(define base 7) (define (plus3 x) (+ x 3)) (plus3 base)")
  end

  test "lists, maps and strings" do
    assert_equal 1, ev("(first '(1 2))")
    assert_equal [ 2 ], ev("(rest '(1 2))")
    assert_equal [ 0, 1, 2 ], ev("(cons 0 '(1 2))")
    assert_equal 3, ev("(count '(a b c))")
    assert_equal true, ev("(empty? '())")
    assert_equal BigDecimal("6.5"), ev("(sum '(1 2 3.5))")
    assert_equal "Total: 6.5 :money", ev(%((str "Total: " (sum '(1 2 3.5)) " " :money)))
    assert_equal 9, ev("(get (data) :price)", functions: { "data" => -> { { price: 9 } } })
  end

  test "only what Sakuya registers exists: nothing from Ruby or the system" do
    assert_match "I don’t know “system”", assert_raises(Lisp::Error) { ev(%((system "ls"))) }.message
    assert_raises(Lisp::Error) { ev(%((File.read "/etc/passwd"))) }
    assert_raises(Lisp::Error) { ev(%(("upcase" "hello"))) }
    assert_equal 12, ev("(sales)", functions: { "sales" => -> { 12 } })
    assert_match "takes 0 and you gave it 1", assert_raises(Lisp::Error) { ev("(sales 1)", functions: { "sales" => -> { 12 } }) }.message
  end

  test "an endless loop or recursion is cut off" do
    assert_raises(Lisp::Exhausted) { ev("(define (f x) (f x)) (f 1)") }
    assert_raises(Lisp::Exhausted) { ev("(define (g n) (+ 1 (g n))) (g 1)", steps: 1_000_000) }
    assert_equal 100, ev("(define (h n) (if (= n 0) 0 (+ 1 (h (- n 1))))) (h 100)", depth: 150)
  end

  test "define does not touch the base functions of other programs" do
    ev("(define (+ a b) 0)")
    assert_equal 3, ev("(+ 1 2)")
  end

  test "to_text writes values as they look in the program" do
    assert_equal %((1 "a" :b 2.5 nil true)), Lisp.to_text(ev(%((list 1 "a" :b 2.5 nil true))))
  end
end
