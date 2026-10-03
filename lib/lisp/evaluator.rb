module Lisp
  # Evaluates forms, counting steps and depth. Special forms (if, let, define…) are resolved
  # here; everything else is applying a function to its already evaluated arguments.
  class Evaluator
    SPECIAL = %w[quote if cond when unless and or let define lambda fn do].freeze

    def initialize(steps:, depth:)
      @steps = steps
      @depth = depth
      @level = 0
    end

    def evaluate(form, environment)
      spend!
      case form
      when Sym then environment.search(form.name)
      when Array
        return [] if form.empty?
        head = form.first
        if head.is_a?(Sym) && SPECIAL.include?(head.name)
          special_form(head.name, form.drop(1), environment)
        else
          function = evaluate(head, environment)
          apply(function, form.drop(1).map { |f| evaluate(f, environment) })
        end
      else form
      end
    end

    # Also used by the natives that call the program's functions (map, filter, reduce).
    def apply(function, arguments)
      case function
      when Native
        unless function.arity.cover?(arguments.size)
          raise Error, I18n.t("lisp.errors.arity", name: function.name, expected: describe(function.arity), given: arguments.size)
        end
        function.with_evaluator ? function.block.call(self, *arguments) : function.block.call(*arguments)
      when Procedure
        if function.parameters.size != arguments.size
          raise Error, I18n.t("lisp.errors.arity", name: function.name || I18n.t("lisp.errors.the_function"), expected: function.parameters.size, given: arguments.size)
        end
        inside do
          local = Environment.new(function.environment)
          function.parameters.zip(arguments) { |p, v| local.define(p, v) }
          sequence(function.body, local)
        end
      else raise Error, I18n.t("lisp.errors.not_a_function", value: Lisp.to_text(function))
      end
    end

    private

    def special_form(name, args, environment)
      case name
      when "quote"
        require(name, args, 1..1)
        args.first
      when "if"
        require(name, args, 2..3)
        truth?(evaluate(args[0], environment)) ? evaluate(args[1], environment) : (args[2] && evaluate(args[2], environment))
      when "cond"
        args.each do |clause|
          raise Error, I18n.t("lisp.errors.cond_clause") unless clause.is_a?(Array) && clause.any?
          test = clause.first
          return sequence(clause.drop(1), environment) if test == Sym.new("else") || truth?(evaluate(test, environment))
        end
        nil
      when "when", "unless"
        require(name, args, 1..)
        meets = truth?(evaluate(args.first, environment))
        meets == (name == "when") ? sequence(args.drop(1), environment) : nil
      when "and"
        args.reduce(true) { |_, f| (v = evaluate(f, environment)) && truth?(v) ? v : (return v) }
      when "or"
        args.each { |f| (v = evaluate(f, environment)) && truth?(v) && (return v) }
        false
      when "let"
        require(name, args, 1..)
        pairs = args.first
        raise Error, I18n.t("lisp.errors.let_syntax") unless pairs.is_a?(Array) && pairs.all? { |p| p.is_a?(Array) && p.size == 2 && p.first.is_a?(Sym) }
        local = Environment.new(environment)
        pairs.each { |n, v| local.define(n.name, evaluate(v, local)) }
        sequence(args.drop(1), local)
      when "define"
        require(name, args, 2..)
        destination = args.first
        if destination.is_a?(Array)
          name_fn, *parameters = destination
          environment.define(name_fn.name, procedure(parameters, args.drop(1), environment, name_fn.name))
        elsif destination.is_a?(Sym)
          require(name, args, 2..2)
          environment.define(destination.name, evaluate(args[1], environment))
        else raise Error, I18n.t("lisp.errors.define_syntax")
        end
        nil
      when "lambda", "fn"
        require(name, args, 2..)
        raise Error, I18n.t("lisp.errors.lambda_syntax", name: name) unless args.first.is_a?(Array)
        procedure(args.first, args.drop(1), environment, nil)
      when "do"
        sequence(args, environment)
      end
    end

    def procedure(parameters, body, environment, name)
      raise Error, I18n.t("lisp.errors.parameter_names") unless parameters.all?(Sym)
      Procedure.new(parameters: parameters.map(&:name), body: body, environment: environment, name: name)
    end

    def sequence(forms, environment)
      forms.reduce(nil) { |_, f| evaluate(f, environment) }
    end

    def truth?(value) = !(value.nil? || value == false)

    def spend!
      @steps -= 1
      raise Exhausted, I18n.t("lisp.errors.too_many_steps") if @steps.negative?
    end

    def inside
      @level += 1
      raise Exhausted, I18n.t("lisp.errors.too_deep") if @level > @depth
      yield
    ensure
      @level -= 1
    end

    def require(name, args, range)
      raise Error, I18n.t("lisp.errors.arity", name: name, expected: describe(range), given: args.size) unless range.cover?(args.size)
    end

    def describe(range)
      if range.end.nil? then I18n.t("lisp.errors.at_least", count: range.begin)
      elsif range.begin == range.end then range.begin.to_s
      else I18n.t("lisp.errors.between", from: range.begin, to: range.end)
      end
    end
  end
end
