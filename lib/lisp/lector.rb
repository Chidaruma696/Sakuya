module Lisp
  # Convierte el texto en formas: listas (Array), símbolos, números, cadenas y palabras clave.
  # `;` comenta hasta el final de la línea y 'x es (quote x).
  module Lector
    TOKEN = /\G(?:(?<espacio>\s+|;[^\n]*)|(?<abre>\()|(?<cierra>\))|(?<cita>')|(?<cadena>"(?:[^"\\]|\\.)*")|(?<atomo>[^\s()'";]+)|(?<mala>"))/m
    ENTERO = /\A[-+]?\d+\z/
    DECIMAL = /\A[-+]?\d*\.\d+\z/
    HONDO = 64 # paréntesis anidados; más que eso no es una regla, es un accidente

    def self.leer(texto)
      texto = texto.to_s
      raise ErrorDeLectura, "el programa pasa de #{LARGO_MAXIMO} caracteres" if texto.length > LARGO_MAXIMO
      pila = [ [] ]
      citas = [ [] ]
      pos = 0
      while pos < texto.length
        m = TOKEN.match(texto, pos) or raise ErrorDeLectura, "no entiendo lo que sigue en la línea #{linea(texto, pos)}"
        if m[:abre]
          raise ErrorDeLectura, "demasiados paréntesis anidados en la línea #{linea(texto, pos)}" if pila.size > HONDO
          pila.push([])
          citas.push([])
        elsif m[:cierra]
          raise ErrorDeLectura, "sobra un ) en la línea #{linea(texto, pos)}" if pila.size == 1
          raise ErrorDeLectura, "falta qué citar antes del ) en la línea #{linea(texto, pos)}" if citas.last.any?
          lista = pila.pop
          citas.pop
          agregar(pila, citas, lista)
        elsif m[:cita]
          citas.last.push(true)
        elsif m[:cadena]
          agregar(pila, citas, desescapar(m[:cadena][1..-2]))
        elsif m[:atomo]
          agregar(pila, citas, atomo(m[:atomo]))
        elsif m[:mala]
          raise ErrorDeLectura, "una cadena sin cerrar en la línea #{linea(texto, pos)}"
        end
        pos = m.end(0)
      end
      raise ErrorDeLectura, "falta cerrar #{pila.size - 1} paréntesis" if pila.size > 1
      raise ErrorDeLectura, "falta qué citar al final" if citas.last.any?
      pila.first
    end

    def self.agregar(pila, citas, forma)
      forma = [ Simbolo.new("quote"), forma ] while citas.last.pop
      pila.last.push(forma)
    end

    def self.atomo(texto)
      case texto
      when ENTERO then Integer(texto, 10)
      when DECIMAL then BigDecimal(texto)
      when "true" then true
      when "false" then false
      when "nil" then nil
      when /\A:[^:]+\z/ then texto[1..].to_sym
      else Simbolo.new(texto)
      end
    end

    def self.desescapar(texto)
      texto.gsub(/\\(.)/) { { "n" => "\n", "t" => "\t" }.fetch($1, $1) }
    end

    def self.linea(texto, pos) = texto[0, pos].count("\n") + 1

    private_class_method :agregar, :atomo, :desescapar, :linea
  end
end
