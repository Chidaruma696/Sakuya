# El gancho al cerrar una venta: con el ticket completo (y cada precio ya juzgado por la regla del
# precio), una regla en el Lisp de Sakuya mira la venta entera antes de cobrarla, y decide.
#
# Contrato v1. Recibe, en pesos: (total), (change) el cambio, (paid-with :cash|:transfer|:deposit)
# lo pagado de esa forma; además (lines) cuántos renglones, (products) la lista de claves,
# (quantity-of "CLAVE") cuánto se lleva de ese producto, (hour) la hora (0-23), (weekday) el día
# (1 lunes … 7 domingo) y (authorized), verdadero si quien cobra tiene caja.forzar_venta.
# Devuelve (allow), (to-review motivo) o (reject motivo).
module ReglaVenta
  VERSION = 1

  DE_FABRICA = <<~LISP
    ; The whole ticket, right before charging it. Each price was already judged by the price rule.
    ; Answer (allow), (to-review "why") or (reject "why").
    ; Out of the box nothing else stops a sale.
    (allow)
  LISP

  FORMAS = { cash: "efectivo", transfer: "transferencia", deposit: "deposito", credit: "credito" }.freeze
  MOTIVOS = %i[].freeze
  FUNCIONES = %w[total change paid-with lines products quantity-of hour weekday authorized].freeze
  EJEMPLO = <<~LISP
    (cond ((and (> (quantity-of "BEER") 0) (>= (hour) 22)) (reject "No beer after 10 pm"))
          ((> (total) 20000) (to-review "Big sale"))
          (else (allow)))
  LISP

  extend Gancho

  CASO = "reglas/caso_venta".freeze # el caso de prueba del editor

  # renglones: [{ clave:, cantidad: }]; pagos: { "efectivo" => centavos, … }
  Datos = Data.define(:total, :cambio, :renglones, :pagos, :momento, :autorizado)

  def self.decidir(datos, codigo:)
    decidir_con(codigo, datos)
  end

  def self.datos(lineas, pagos, total:, cambio:, autorizado:, momento: Time.current)
    Datos.new(total: total, cambio: cambio, renglones: lineas.map { |l| { clave: l[:producto].clave, cantidad: l[:cantidad] } },
              pagos: pagos.group_by { |p| p[:forma] }.transform_values { |ps| ps.sum { |p| p[:monto_centavos] } }, momento: momento, autorizado: autorizado)
  end

  # El caso de prueba del editor: una venta de verdad (por folio) o una inventada con claves,
  # total, forma de pago y hora.
  def self.caso(params, sucursal)
    folio = params[:venta].to_s.strip.upcase.presence
    { folio_venta: folio, venta: (Venta.where(sucursal: sucursal).find_by(folio: folio) if folio),
      claves: params[:claves].presence || Producto.activos.order(:nombre).limit(2).pluck(:clave).join(", "),
      total: params[:total].present? ? Dinero.centavos(params[:total]) : 25_000, forma: params[:forma].presence_in(Pago::FORMAS) || "efectivo",
      hora: (params[:hora].presence || Time.current.hour).to_i.clamp(0, 23), autorizado: params[:autorizado] == "1" }
  end

  def self.probar(codigo, caso)
    raise Lisp::Error, I18n.t("regla_precio.venta_no_existe", folio: caso[:folio_venta]) if caso[:folio_venta] && !caso[:venta]
    evaluar(codigo, caso[:venta] ? de_venta(caso[:venta], caso[:autorizado]) : inventada(caso))
  end

  def self.de_venta(venta, autorizado)
    Datos.new(total: venta.total_centavos, cambio: venta.cambio_centavos, renglones: venta.lineas.includes(:producto).map { |l| { clave: l.producto.clave, cantidad: l.cantidad } },
              pagos: venta.pagos.group(:forma).sum(:monto_centavos), momento: venta.created_at, autorizado: autorizado)
  end

  def self.inventada(caso)
    renglones = caso[:claves].split(",").map(&:strip).compact_blank.map { |c| { clave: c.upcase, cantidad: BigDecimal("1") } }
    Datos.new(total: caso[:total], cambio: 0, renglones: renglones, pagos: { caso[:forma] => caso[:total] },
              momento: Time.current.change(hour: caso[:hora]), autorizado: caso[:autorizado])
  end

  def self.textos = "regla_venta"

  def self.interpolar(_datos) = {}

  def self.funciones(datos)
    pesos = ->(c) { BigDecimal(c.to_i) / 100 }
    {
      "total" => -> { pesos.(datos.total) },
      "change" => -> { pesos.(datos.cambio) },
      "paid-with" => ->(forma) { pesos.(datos.pagos.fetch(FORMAS[forma] || raise(Lisp::Error, I18n.t("regla_venta.forma", formas: FORMAS.keys.join(" :"))), 0)) },
      "lines" => -> { datos.renglones.size },
      "products" => -> { datos.renglones.map { |r| r[:clave] }.uniq },
      "quantity-of" => ->(clave) { datos.renglones.select { |r| r[:clave] == clave.to_s.upcase }.sum(BigDecimal("0")) { |r| r[:cantidad] } },
      "hour" => -> { datos.momento.hour },
      "weekday" => -> { datos.momento.to_date.cwday },
      "authorized" => -> { datos.autorizado }
    }
  end

  private_class_method :funciones, :interpolar, :textos, :de_venta, :inventada
end
