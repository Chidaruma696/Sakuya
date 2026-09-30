module Lisp
  # Los nombres visibles en un punto del programa, encadenados hasta el entorno base.
  class Entorno
    def initialize(padre = nil)
      @padre = padre
      @nombres = {}
    end

    def definir(nombre, valor)
      @nombres[nombre] = valor
    end

    def buscar(nombre)
      entorno = self
      while entorno
        return entorno.propio(nombre) if entorno.tiene?(nombre)
        entorno = entorno.padre
      end
      raise Error, "no conozco «#{nombre}»"
    end

    def congelar!
      @nombres.freeze
      self
    end

    protected

    attr_reader :padre

    def tiene?(nombre) = @nombres.key?(nombre)
    def propio(nombre) = @nombres[nombre]
  end
end
