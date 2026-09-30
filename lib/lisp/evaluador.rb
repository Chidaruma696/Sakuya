module Lisp
  # Evalúa formas contando pasos y profundidad. Las formas especiales (if, let, define…) se
  # resuelven aquí; todo lo demás es aplicar una función a sus argumentos ya evaluados.
  class Evaluador
    ESPECIALES = %w[quote if cond when unless and or let define lambda fn do].freeze

    def initialize(pasos:, profundidad:)
      @pasos = pasos
      @profundidad = profundidad
      @nivel = 0
    end

    def evaluar(forma, entorno)
      gastar!
      case forma
      when Simbolo then entorno.buscar(forma.nombre)
      when Array
        return [] if forma.empty?
        cabeza = forma.first
        if cabeza.is_a?(Simbolo) && ESPECIALES.include?(cabeza.nombre)
          especial(cabeza.nombre, forma.drop(1), entorno)
        else
          funcion = evaluar(cabeza, entorno)
          aplicar(funcion, forma.drop(1).map { |f| evaluar(f, entorno) })
        end
      else forma
      end
    end

    # También lo usan las nativas que llaman a funciones del programa (map, filter, reduce).
    def aplicar(funcion, argumentos)
      case funcion
      when Nativa
        unless funcion.aridad.cover?(argumentos.size)
          raise Error, "#{funcion.nombre} recibe #{describir(funcion.aridad)} y le diste #{argumentos.size}"
        end
        funcion.con_evaluador ? funcion.bloque.call(self, *argumentos) : funcion.bloque.call(*argumentos)
      when Procedimiento
        if funcion.parametros.size != argumentos.size
          raise Error, "#{funcion.nombre || "la función"} recibe #{funcion.parametros.size} y le diste #{argumentos.size}"
        end
        adentro do
          local = Entorno.new(funcion.entorno)
          funcion.parametros.zip(argumentos) { |p, v| local.definir(p, v) }
          secuencia(funcion.cuerpo, local)
        end
      else raise Error, "#{Lisp.a_texto(funcion)} no es una función"
      end
    end

    private

    def especial(nombre, args, entorno)
      case nombre
      when "quote"
        exigir(nombre, args, 1..1)
        args.first
      when "if"
        exigir(nombre, args, 2..3)
        verdad?(evaluar(args[0], entorno)) ? evaluar(args[1], entorno) : (args[2] && evaluar(args[2], entorno))
      when "cond"
        args.each do |clausula|
          raise Error, "cada cláusula de cond es (prueba valor…)" unless clausula.is_a?(Array) && clausula.any?
          prueba = clausula.first
          return secuencia(clausula.drop(1), entorno) if prueba == Simbolo.new("else") || verdad?(evaluar(prueba, entorno))
        end
        nil
      when "when", "unless"
        exigir(nombre, args, 1..)
        cumple = verdad?(evaluar(args.first, entorno))
        cumple == (nombre == "when") ? secuencia(args.drop(1), entorno) : nil
      when "and"
        args.reduce(true) { |_, f| (v = evaluar(f, entorno)) && verdad?(v) ? v : (return v) }
      when "or"
        args.each { |f| (v = evaluar(f, entorno)) && verdad?(v) && (return v) }
        false
      when "let"
        exigir(nombre, args, 1..)
        pares = args.first
        raise Error, "let va así: (let ((nombre valor) …) cuerpo…)" unless pares.is_a?(Array) && pares.all? { |p| p.is_a?(Array) && p.size == 2 && p.first.is_a?(Simbolo) }
        local = Entorno.new(entorno)
        pares.each { |n, v| local.definir(n.nombre, evaluar(v, local)) }
        secuencia(args.drop(1), local)
      when "define"
        exigir(nombre, args, 2..)
        destino = args.first
        if destino.is_a?(Array)
          nombre_fn, *parametros = destino
          entorno.definir(nombre_fn.nombre, procedimiento(parametros, args.drop(1), entorno, nombre_fn.nombre))
        elsif destino.is_a?(Simbolo)
          exigir(nombre, args, 2..2)
          entorno.definir(destino.nombre, evaluar(args[1], entorno))
        else raise Error, "define va así: (define nombre valor) o (define (nombre args…) cuerpo…)"
        end
        nil
      when "lambda", "fn"
        exigir(nombre, args, 2..)
        raise Error, "#{nombre} va así: (#{nombre} (args…) cuerpo…)" unless args.first.is_a?(Array)
        procedimiento(args.first, args.drop(1), entorno, nil)
      when "do"
        secuencia(args, entorno)
      end
    end

    def procedimiento(parametros, cuerpo, entorno, nombre)
      raise Error, "los parámetros van como nombres" unless parametros.all?(Simbolo)
      Procedimiento.new(parametros: parametros.map(&:nombre), cuerpo: cuerpo, entorno: entorno, nombre: nombre)
    end

    def secuencia(formas, entorno)
      formas.reduce(nil) { |_, f| evaluar(f, entorno) }
    end

    def verdad?(valor) = !(valor.nil? || valor == false)

    def gastar!
      @pasos -= 1
      raise Agotado, "el programa se pasó de pasos (¿un ciclo sin fin?)" if @pasos.negative?
    end

    def adentro
      @nivel += 1
      raise Agotado, "el programa se metió demasiado hondo (¿una recursión sin fin?)" if @nivel > @profundidad
      yield
    ensure
      @nivel -= 1
    end

    def exigir(nombre, args, rango)
      raise Error, "#{nombre} recibe #{describir(rango)} y le diste #{args.size}" unless rango.cover?(args.size)
    end

    def describir(rango)
      if rango.end.nil? then "al menos #{rango.begin}"
      elsif rango.begin == rango.end then rango.begin.to_s
      else "de #{rango.begin} a #{rango.end}"
      end
    end
  end
end
