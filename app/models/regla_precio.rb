# El gancho del precio: cada renglón que se cobra pasa por una regla en el Lisp de Sakuya que
# mira el precio que puso la caja y decide. El piso de Ajustes › Caja no lo cruza nadie, ni con
# regla; lo demás es de la regla.
#
# Contrato v1. Recibe, en pesos: (price) lo que se cobra, (list-price) el catálogo de la
# sucursal, (regular-price) lo que toca (la mejor promoción o el catálogo), (discount) cuánto
# por ciento por debajo de lo que toca (0 si no hay rebaja); además (quantity), (product) la
# clave y (authorized), verdadero si quien autoriza tiene caja.bajar_precio. Devuelve (allow),
# (to-review motivo) o (reject motivo).
module ReglaPrecio
  VERSION = 1

  DE_FABRICA = <<~LISP
    ; Each line at the till. (price) is what is being charged; (regular-price) is the list price or the promotion.
    ; Answer (allow), (to-review "why") or (reject "why").
    ; Below the regular price it stops: only someone allowed to lower prices can sell it, and it goes to review.
    (if (>= (price) (regular-price))
        (allow)
        (reject :below-price))
  LISP

  MOTIVOS = %i[below-price].freeze

  extend Gancho

  Datos = Data.define(:producto, :cantidad, :precio, :catalogo, :regular, :autorizado) do
    def pesos(centavos) = BigDecimal(centavos.to_i) / 100
    def descuento = regular.positive? && precio < regular ? ((regular - precio) * 100 / BigDecimal(regular)).round(2) : BigDecimal("0")
  end

  def self.decidir(datos, codigo:)
    decidir_con(codigo, datos)
  end

  def self.textos = "regla_precio"

  def self.interpolar(datos)
    { producto: datos.producto.nombre, precio: Dinero.pesos(datos.precio), regular: Dinero.pesos(datos.regular) }
  end

  def self.funciones(datos)
    {
      "price" => -> { datos.pesos(datos.precio) },
      "list-price" => -> { datos.pesos(datos.catalogo) },
      "regular-price" => -> { datos.pesos(datos.regular) },
      "discount" => -> { datos.descuento },
      "quantity" => -> { datos.cantidad },
      "product" => -> { datos.producto.clave },
      "authorized" => -> { datos.autorizado }
    }
  end

  private_class_method :funciones, :interpolar, :textos
end
