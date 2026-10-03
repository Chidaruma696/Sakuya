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

  CASO = "reglas/caso_precio".freeze # el caso de prueba del editor

  Datos = Data.define(:producto, :cantidad, :precio, :catalogo, :regular, :autorizado) do
    def pesos(centavos) = BigDecimal(centavos.to_i) / 100
    def descuento = regular.positive? && precio < regular ? ((regular - precio) * 100 / BigDecimal(regular)).round(2) : BigDecimal("0")
  end

  def self.decidir(datos, codigo:)
    decidir_con(codigo, datos)
  end

  # El caso de prueba del editor: un producto del catálogo, cuánto se lleva, a qué precio y si
  # cobra alguien con permiso. Lo que toca sale del catálogo y las promociones de la sucursal.
  def self.caso(params, sucursal)
    producto = Producto.activos.find_by(clave: params[:producto].to_s.upcase) || Producto.activos.order(:nombre).find { |p| p.precio_centavos_en(sucursal).positive? }
    cantidad = BigDecimal(params[:cantidad].presence || "1") rescue BigDecimal("1")
    catalogo = producto ? producto.precio_centavos_en(sucursal) : 0
    regular = producto ? (Promocion.mejor(producto, sucursal, cantidad, catalogo)&.first || catalogo) : 0
    precio = params[:precio].present? ? Dinero.centavos(params[:precio]) : regular
    venta = Venta.where(sucursal: sucursal).find_by(folio: params[:venta].to_s.strip.upcase) if params[:venta].present?
    { producto: producto, cantidad: cantidad, precio: precio, catalogo: catalogo, regular: regular, autorizado: params[:autorizado] == "1",
      venta: venta, folio_venta: params[:venta].to_s.strip.upcase.presence, sucursal: sucursal }
  end

  # Con una venta de verdad, repasa sus renglones tal como se cobraron (lo que tocaba se recalcula
  # con el catálogo de entonces y las promociones de hoy) y devuelve una decisión por renglón.
  def self.probar(codigo, caso)
    raise Lisp::Error, I18n.t("regla_precio.venta_no_existe", folio: caso[:folio_venta]) if caso[:folio_venta] && !caso[:venta]
    return probar_venta(codigo, caso) if caso[:venta]
    raise Lisp::Error, I18n.t("regla_precio.sin_productos") unless caso[:producto]
    evaluar(codigo, Datos.new(producto: caso[:producto], cantidad: caso[:cantidad], precio: caso[:precio], catalogo: caso[:catalogo], regular: caso[:regular], autorizado: caso[:autorizado]))
  end

  def self.probar_venta(codigo, caso)
    caso[:venta].lineas.includes(:producto, :autorizado_por).map do |l|
      regular = Promocion.mejor(l.producto, caso[:sucursal], l.cantidad, l.catalogo_centavos)&.first || l.catalogo_centavos
      datos = Datos.new(producto: l.producto, cantidad: l.cantidad, precio: l.precio_centavos, catalogo: l.catalogo_centavos, regular: regular,
                        autorizado: caso[:autorizado] || l.autorizado_por.present?)
      [ I18n.t("caja.cobro", producto: "#{l.producto.nombre} × #{l.cantidad.to_s("F")}", precio: Dinero.pesos(l.precio_centavos), regular: Dinero.pesos(regular)), evaluar(codigo, datos), datos.autorizado ]
    end
  end

  FUNCIONES = %w[price list-price regular-price discount quantity product authorized].freeze
  EJEMPLO = <<~LISP
    (cond ((= (discount) 0) (allow))
          ((= (product) "CATS") (reject "Never discounted"))
          ((<= (discount) 5) (allow))
          (else (to-review "Big discount")))
  LISP

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

  private_class_method :funciones, :interpolar, :textos, :probar_venta
end
