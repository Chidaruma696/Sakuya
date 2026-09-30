# Qué es lo que se escaneó: un producto por su código de barras, o por PLU o clave tecleados.
# Lo usan la caja, la recepción y el conteo.
module Escaneo
  Resultado = Struct.new(:tipo, :producto, keyword_init: true) do
    def producto? = tipo == :producto
  end

  def self.resolver(texto)
    texto = texto.to_s.strip
    return nil if texto.empty?

    if (codigo = CodigoBarras.includes(:producto).find_by(codigo: Barcode.variantes(texto)))
      return Resultado.new(tipo: :producto, producto: codigo.producto)
    end
    digitos = Barcode.digitos(texto)
    if digitos == texto && (producto = Producto.activos.find_by(plu: digitos.to_i))
      return Resultado.new(tipo: :producto, producto: producto)
    end
    if (producto = Producto.activos.find_by(clave: texto.upcase))
      return Resultado.new(tipo: :producto, producto: producto)
    end
    nil
  end
end
