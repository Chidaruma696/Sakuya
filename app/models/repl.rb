# El REPL de solo lectura: preguntarle cosas a los datos en vivo con el Lisp de Sakuya. Las
# consultas devuelven listas de mapas ({:folio "B-00012" :total 126.00 …}) que se filtran, ordenan
# y agrupan con las funciones de aquí y las de siempre (map, filter, reduce).
#
# No escribe nada: además de que el Lisp solo sabe llamar lo que se le da, cada evaluación corre
# con las escrituras bloqueadas en la base, con límite de pasos y de filas.
#
#   (sum-of :total (sales "2026-10-01" (today)))
#   (sort-by-desc :balance (customers))
#   (count-by :cashier (sales))
module Repl
  FILAS = 500
  PASOS = 200_000

  CONSULTAS = %w[today days-ago sales sale-lines products stock customers cash-counts reviews rules].freeze
  HERRAMIENTAS = %w[where sort-by sort-by-desc group-by count-by sum-of pluck take].freeze
  # Cómo se llaman, para la referencia del REPL.
  FIRMAS = {
    "today" => "(today)", "days-ago" => "(days-ago 7)", "sales" => "(sales [from] [to])", "sale-lines" => "(sale-lines [from] [to])",
    "products" => "(products)", "stock" => "(stock [\"CODE\"])", "customers" => "(customers)", "cash-counts" => "(cash-counts [from] [to])",
    "reviews" => "(reviews)", "rules" => "(rules)", "where" => "(where :key value list)", "sort-by" => "(sort-by :key list)",
    "sort-by-desc" => "(sort-by-desc :key list)", "group-by" => "(group-by :key list)", "count-by" => "(count-by :key list)",
    "sum-of" => "(sum-of :key list)", "pluck" => "(pluck :key list)", "take" => "(take n list)"
  }.freeze

  # Evalúa el texto y devuelve el valor; levanta Lisp::Error con lo que falló.
  def self.evaluar(texto, sucursales:)
    solo_lectura { Lisp.ejecutar(texto, funciones: funciones(sucursales), pasos: PASOS) }
  end

  # Corre el bloque con las escrituras bloqueadas en la base; si algo intenta escribir, es un error.
  def self.solo_lectura(&)
    ActiveRecord::Base.while_preventing_writes(&)
  rescue ActiveRecord::ReadOnlyError
    raise Lisp::Error, I18n.t("repl.solo_lectura")
  end

  def self.funciones(sucursales)
    consultas(Consultas.new(sucursales)).merge(herramientas)
  end

  def self.consultas(c)
    {
      "today" => -> { Date.current.iso8601 },
      "days-ago" => ->(n) { (Date.current - Lisp::Base.numero!(n, "days-ago").to_i).iso8601 },
      "sales" => ->(*rango) { c.ventas(*rango) },
      "sale-lines" => ->(*rango) { c.renglones(*rango) },
      "products" => -> { c.productos },
      "stock" => ->(*clave) { c.existencias(*clave) },
      "customers" => -> { c.clientes },
      "cash-counts" => ->(*rango) { c.cortes(*rango) },
      "reviews" => -> { c.revisiones },
      "rules" => -> { c.reglas }
    }
  end

  def self.herramientas
    lista = ->(l, quien) { Lisp::Base.lista!(l, quien) }
    campo = ->(fila, k) { fila.is_a?(Hash) ? fila[k] : raise(Lisp::Error, I18n.t("repl.errores.no_es_mapa", valor: Lisp.a_texto(fila))) }
    ordenable = ->(v) { v.nil? ? [ 1, 0 ] : [ 0, v.is_a?(Numeric) ? v : v.to_s ] }
    {
      "where" => ->(k, v, l) { lista.(l, "where").select { |f| campo.(f, k) == v } },
      "sort-by" => ->(k, l) { lista.(l, "sort-by").sort_by { |f| ordenable.(campo.(f, k)) } },
      "sort-by-desc" => ->(k, l) { lista.(l, "sort-by-desc").sort_by { |f| ordenable.(campo.(f, k)) }.reverse },
      "group-by" => ->(k, l) { lista.(l, "group-by").group_by { |f| campo.(f, k) } },
      "count-by" => ->(k, l) { lista.(l, "count-by").group_by { |f| campo.(f, k) }.transform_values(&:size) },
      "sum-of" => ->(k, l) { lista.(l, "sum-of").sum(BigDecimal("0")) { |f| campo.(f, k) || 0 } },
      "pluck" => ->(k, l) { lista.(l, "pluck").map { |f| campo.(f, k) } }
    }
  end

  private_class_method :funciones, :consultas, :herramientas

  # Las consultas en sí: solo leen, solo de las sucursales que se ven, y en pesos.
  class Consultas
    def initialize(sucursales)
      @sucursales = sucursales
    end

    def ventas(desde = nil, hasta = nil)
      ventas_de(desde, hasta).includes(:sucursal, :usuario, :cliente).map do |v|
        { folio: v.folio, date: v.fecha_negocio.iso8601, branch: v.sucursal.nombre, cashier: v.usuario.nombre, customer: v.cliente&.nombre,
          total: pesos(v.total_centavos), change: pesos(v.cambio_centavos), status: v.estado }
      end
    end

    def renglones(desde = nil, hasta = nil)
      VentaLinea.where(venta: ventas_de(desde, hasta)).includes(:venta, :producto).limit(FILAS + 1).map do |l|
        { folio: l.venta.folio, date: l.venta.fecha_negocio.iso8601, code: l.producto.clave, product: l.producto.nombre,
          quantity: BigDecimal(l.cantidad.to_s), price: pesos(l.precio_centavos), amount: pesos(l.importe_centavos) }
      end
    end

    def productos
      Producto.order(:nombre).limit(FILAS + 1).map do |p|
        { code: p.clave, name: p.nombre, unit: p.unidad, price: pesos(p.precio_centavos), active: p.activo }
      end
    end

    def existencias(clave = nil)
      e = Existencia.where(sucursal: @sucursales).includes(:sucursal, :producto).joins(:producto).order("productos.nombre")
      e = e.where(productos: { clave: texto!(clave, "stock").upcase }) if clave
      e.limit(FILAS + 1).map { |x| { branch: x.sucursal.nombre, code: x.producto.clave, product: x.producto.nombre, quantity: BigDecimal(x.cantidad.to_s) } }
    end

    def clientes
      return [] unless Modulo.activo?("clientes")
      saldos = MovimientoCredito.group(:cliente_id).sum(:monto_centavos)
      Cliente.order(:nombre).limit(FILAS + 1).map do |c|
        { name: c.nombre, balance: pesos(saldos[c.id] || 0), limit: pesos(c.limite_credito_centavos), active: c.activo }
      end
    end

    def cortes(desde = nil, hasta = nil)
      d, h = rango(desde, hasta)
      Corte.where(sucursal: @sucursales, abierto_en: d.beginning_of_day..h.end_of_day).includes(:sucursal, :usuario).order(:abierto_en).limit(FILAS + 1).map do |c|
        { folio: c.folio, branch: c.sucursal.nombre, cashier: c.usuario.nombre, status: c.estado, opened: c.abierto_en.iso8601,
          expected: c.esperado_centavos && pesos(c.esperado_centavos), counted: c.contado_centavos && pesos(c.contado_centavos),
          difference: c.diferencia_centavos && pesos(c.diferencia_centavos) }
      end
    end

    def revisiones
      Revision.pendientes.where(sucursal: @sucursales).includes(:usuario, :revisable).order(:created_at).limit(FILAS + 1).map do |r|
        { when: r.created_at.iso8601, who: r.usuario.nombre, what: r.descripcion, reason: r.motivo, value: pesos(r.valor_centavos), stopped: r.frenado }
      end
    end

    def reglas
      Regla::GANCHOS.filter_map do |g|
        r = Regla.vigente(g) or next
        { hook: g, contract: r.version, current: Regla.contrato(g), saved: r.created_at.iso8601, by: r.usuario.nombre }
      end
    end

    private

    def ventas_de(desde, hasta)
      d, h = rango(desde, hasta)
      Venta.where(sucursal: @sucursales, fecha_negocio: d..h).order(:id).limit(FILAS + 1)
    end

    # Sin fechas, hoy; con una, ese día; con dos, de una a otra. Fechas como "2026-10-03".
    def rango(desde, hasta)
      d = desde ? fecha!(desde) : Date.current
      h = hasta ? fecha!(hasta) : d
      d <= h ? [ d, h ] : [ h, d ]
    end

    def fecha!(texto)
      Date.iso8601(texto!(texto, "fecha"))
    rescue Date::Error
      raise Lisp::Error, I18n.t("repl.errores.fecha", valor: texto)
    end

    def texto!(x, quien)
      x.is_a?(String) ? x : raise(Lisp::Error, I18n.t("repl.errores.texto", quien: quien, valor: Lisp.a_texto(x)))
    end

    def pesos(centavos) = BigDecimal(centavos.to_i) / 100
  end
end
