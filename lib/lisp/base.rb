module Lisp
  # The functions every program has: numbers, comparisons, lists and strings. Nothing here
  # touches the database or the outside world; each hook registers that with its own functions.
  module Base
    DIVISION_DECIMALS = 20

    def self.environment
      @environment ||= Environment.new.tap do |e|
        FUNCTIONS.each { |name, (arity, block, with_evaluator)| e.define(name, Native.new(name: name, arity: arity, block: block, with_evaluator: !!with_evaluator)) }
      end.freeze!
    end

    # Wraps a Ruby block as a language function; the arity comes from the block.
    def self.native(name, block)
      arity = block.arity.negative? ? ((block.arity.abs - 1)..) : (block.arity..block.arity)
      Native.new(name: name, arity: arity, block: block, with_evaluator: false)
    end

    def self.number!(x, who)
      raise Error, I18n.t("lisp.errors.expects_numbers", who: who, value: Lisp.to_text(x)) unless x.is_a?(Numeric)
      x
    end

    def self.list!(x, who)
      return [] if x.nil?
      raise Error, I18n.t("lisp.errors.expects_list", who: who, value: Lisp.to_text(x)) unless x.is_a?(Array)
      x
    end

    def self.divide(a, b)
      raise Error, I18n.t("lisp.errors.division_by_zero") if b.zero?
      BigDecimal(a.to_s).div(BigDecimal(b.to_s), DIVISION_DECIMALS)
    end

    def self.compare(name, args, &test)
      args.each { |x| number!(x, name) }
      args.each_cons(2).all? { |a, b| test.call(a, b) }
    end

    def self.truth?(x) = !(x.nil? || x == false)

    FUNCTIONS = {
      "+" => [ 0.., ->(*xs) { xs.each { |x| number!(x, "+") }.sum(0) } ],
      "-" => [ 1.., ->(x, *xs) { number!(x, "-"); xs.empty? ? -x : xs.reduce(x) { |a, b| a - number!(b, "-") } } ],
      "*" => [ 0.., ->(*xs) { xs.reduce(1) { |a, b| a * number!(b, "*") } } ],
      "/" => [ 2.., ->(x, *xs) { xs.reduce(number!(x, "/")) { |a, b| divide(a, number!(b, "/")) } } ],
      "round" => [ 1..2, ->(x, d = 0) { number!(x, "round"); BigDecimal(x.to_s).round(d, :half_up).then { |r| d.zero? ? r.to_i : r } } ],
      "abs" => [ 1..1, ->(x) { number!(x, "abs").abs } ],
      "min" => [ 1.., ->(*xs) { xs.each { |x| number!(x, "min") }.min } ],
      "max" => [ 1.., ->(*xs) { xs.each { |x| number!(x, "max") }.max } ],
      "=" => [ 1.., ->(*xs) { xs.each_cons(2).all? { |a, b| a == b } } ],
      "/=" => [ 2..2, ->(a, b) { a != b } ],
      "<" => [ 1.., ->(*xs) { compare("<", xs) { |a, b| a < b } } ],
      ">" => [ 1.., ->(*xs) { compare(">", xs) { |a, b| a > b } } ],
      "<=" => [ 1.., ->(*xs) { compare("<=", xs) { |a, b| a <= b } } ],
      ">=" => [ 1.., ->(*xs) { compare(">=", xs) { |a, b| a >= b } } ],
      "not" => [ 1..1, ->(x) { !truth?(x) } ],
      "list" => [ 0.., ->(*xs) { xs } ],
      "first" => [ 1..1, ->(l) { list!(l, "first").first } ],
      "rest" => [ 1..1, ->(l) { list!(l, "rest").drop(1) } ],
      "nth" => [ 2..2, ->(l, i) { list!(l, "nth")[number!(i, "nth").to_i] } ],
      "count" => [ 1..1, ->(l) { l.is_a?(String) ? l.length : list!(l, "count").size } ],
      "empty?" => [ 1..1, ->(l) { list!(l, "empty?").empty? } ],
      "cons" => [ 2..2, ->(x, l) { [ x, *list!(l, "cons") ] } ],
      "append" => [ 0.., ->(*ls) { ls.flat_map { |l| list!(l, "append") } } ],
      "reverse" => [ 1..1, ->(l) { list!(l, "reverse").reverse } ],
      "take" => [ 2..2, ->(n, l) { list!(l, "take").first(number!(n, "take").to_i) } ],
      "sum" => [ 1..1, ->(l) { list!(l, "sum").each { |x| number!(x, "sum") }.sum(0) } ],
      "map" => [ 2..2, ->(ev, f, l) { list!(l, "map").map { |x| ev.apply(f, [ x ]) } }, true ],
      "filter" => [ 2..2, ->(ev, f, l) { list!(l, "filter").select { |x| truth?(ev.apply(f, [ x ])) } }, true ],
      "reduce" => [ 3..3, ->(ev, f, initial, l) { list!(l, "reduce").reduce(initial) { |a, x| ev.apply(f, [ a, x ]) } }, true ],
      "get" => [ 2..3, ->(m, k, other = nil) { m.is_a?(Hash) ? m.fetch(k, other) : raise(Error, I18n.t("lisp.errors.get_expects_map")) } ],
      "str" => [ 0.., ->(*xs) { xs.map { |x| x.is_a?(String) ? x : Lisp.to_text(x) }.join } ],
      "number?" => [ 1..1, ->(x) { x.is_a?(Numeric) } ],
      "string?" => [ 1..1, ->(x) { x.is_a?(String) } ],
      "list?" => [ 1..1, ->(x) { x.is_a?(Array) } ],
      "nil?" => [ 1..1, ->(x) { x.nil? } ]
    }.freeze
  end
end
