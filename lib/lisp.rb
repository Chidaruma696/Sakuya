# Sakuya's Lisp: a small dialect, written here, for each business's rules.
#
# It can only do what Sakuya registers for it: no files, no network, no processes, no access to
# Ruby. Every evaluation carries a step counter and a depth limit, so an endless loop or
# recursion is cut off with an error instead of freezing the till. Money is BigDecimal, never
# float. The language's names are in English, as in Emacs.
#
#   Lisp.run("(+ 1 2.50)")                    # => 0.35e1
#   Lisp.run("(total)", functions: { "total" => -> { 10 } })
module Lisp
  class Error < StandardError; end
  # The text cannot be read: unclosed parentheses, a string with no closing quote…
  class ReadError < Error; end
  # Ran out of steps or depth.
  class Exhausted < Error; end

  MAX_LENGTH = 20_000

  # A symbol in the program (a name), distinct from a string and from a keyword (:x).
  Sym = Data.define(:name) do
    def to_s = name
  end

  # A function written in the program: (lambda (x) …) or (define (f x) …).
  Procedure = Data.define(:parameters, :body, :environment, :name)

  # A Sakuya function, written in Ruby. `arity` is a Range; `block` gets the already evaluated
  # arguments and, if it asks for it, the evaluator (for those that call other functions, like map).
  Native = Data.define(:name, :arity, :block, :with_evaluator)

  # Reads and evaluates the whole text; returns the value of the last expression. `prelude` holds
  # already read forms evaluated first, in the same environment (the plugins' functions).
  def self.run(text, functions: {}, steps: 10_000, depth: 100, prelude: [])
    environment = Environment.new(Base.environment)
    functions.each { |name, f| environment.define(name.to_s, f.is_a?(Native) ? f : Base.native(name.to_s, f)) }
    evaluator = Evaluator.new(steps: steps, depth: depth)
    prelude.each { |form| evaluator.evaluate(form, environment) }
    Reader.read(text).reduce(nil) { |_, form| evaluator.evaluate(form, environment) }
  end

  # The value written the way it would be written in the program, for messages and the REPL.
  def self.to_text(value)
    case value
    when nil then "nil"
    when true then "true"
    when false then "false"
    when Sym then value.name
    when Symbol then ":#{value}"
    when String then value.inspect
    when BigDecimal then value.to_s("F")
    when Array then "(#{value.map { |v| to_text(v) }.join(" ")})"
    when Hash then "{#{value.map { |k, v| "#{to_text(k)} #{to_text(v)}" }.join(" ")}}"
    when Procedure then "#<fn #{value.name || I18n.t("lisp.anonymous")}>"
    when Native then "#<fn #{value.name}>"
    else value.to_s
    end
  end
end
