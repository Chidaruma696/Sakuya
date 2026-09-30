# El tablero de Inicio lo describe un programa en el Lisp de Sakuya: qué cifras salen, en qué
# orden, cuáles se calculan a gusto del negocio y qué listas van debajo. El programa solo lee
# (ventas, tickets, existencias…) y devuelve la descripción; lo pinta la vista. Si truena, sale
# el de fábrica y quien puede editarlo ve por qué.
module Tablero
  DE_FABRICA = <<~LISP
    ; The home dashboard. Each (tile ...) is a figure and each (panel ...) a list.
    ; (tile :sales) uses a built-in figure; (tile "Label" value :money) makes your own.
    (dashboard
      (tile :sales)
      (tile :tickets)
      (tile :average-ticket)
      (tile :returns)
      (tile :cash)
      (tile :transfers)
      (tile :deposits)
      (tile :stock-value)
      (panel :top-products)
      (panel :closed-cash-counts)
      (panel :stock-counts))
  LISP

  FORMATOS = %i[money number percent].freeze
  PANELES = %i[top-products closed-cash-counts stock-counts].freeze

  # Cifras de fábrica: la clave de su nombre, su formato y de dónde sale.
  CIFRAS = {
    sales: [ "inicio.ventas", :money, :ventas ],
    tickets: [ "inicio.tickets", :number, :tickets ],
    "average-ticket": [ "inicio.ticket_promedio", :money, :ticket_promedio ],
    returns: [ "inicio.devoluciones", :money, :devoluciones ],
    cash: [ "inicio.efectivo", :money, :efectivo ],
    transfers: [ "inicio.transferencias", :money, :transferencias ],
    deposits: [ "inicio.depositos", :money, :depositos ],
    "stock-value": [ "inicio.inventario_valorizado", :money, :valor_existencias ],
    payable: [ "compras.debemos", :money, :por_pagar ],
    "to-review": [ "revisiones.titulo", :number, :por_revisar ]
  }.freeze

  Pieza = Data.define(:tipo, :titulo, :valor, :formato, :panel, :limite)

  # Arma el tablero con el programa del negocio (o el de fábrica). Devuelve (piezas, error).
  def self.armar(datos, codigo: Regla.vigente("tablero")&.codigo)
    return [ evaluar(DE_FABRICA, datos), nil ] if codigo.blank?
    [ evaluar(codigo, datos), nil ]
  rescue Lisp::Error => e
    [ evaluar(DE_FABRICA, datos), e.message ]
  end

  # Evalúa un programa y devuelve sus piezas, o levanta Lisp::Error con lo que falló.
  def self.evaluar(codigo, datos)
    resultado = Lisp.ejecutar(codigo, funciones: funciones(datos), pasos: 20_000)
    unless resultado.is_a?(Hash) && resultado[:tipo] == :dashboard
      raise Lisp::Error, I18n.t("tablero.errores.sin_dashboard")
    end
    resultado[:piezas]
  end

  def self.funciones(datos)
    lectura = CIFRAS.to_h { |nombre, (_, _, metodo)| [ nombre.to_s, -> { datos.public_send(metodo) } ] }
    lectura.merge(
      "days" => -> { datos.dias },
      "sold" => ->(clave) { datos.vendido(clave) },
      "sales-of" => ->(clave) { datos.vendido_importe(clave) },
      "tile" => Lisp::Nativa.new(nombre: "tile", aridad: 1..3, con_evaluador: false, bloque: ->(*args) { tile(datos, *args) }),
      "panel" => Lisp::Nativa.new(nombre: "panel", aridad: 1..2, con_evaluador: false, bloque: ->(*args) { panel(*args) }),
      "dashboard" => ->(*piezas) { { tipo: :dashboard, piezas: piezas.flatten.compact.each { |p| comprobar_pieza!(p) } } }
    )
  end

  def self.tile(datos, titulo, valor = nil, formato = nil)
    if titulo.is_a?(Symbol)
      clave, de_fabrica, metodo = CIFRAS[titulo] || raise(Lisp::Error, I18n.t("tablero.errores.cifra_desconocida", cifra: titulo, cifras: CIFRAS.keys.join(" :")))
      titulo = I18n.t(clave)
      valor = datos.public_send(metodo) if valor.nil?
      formato ||= de_fabrica
    end
    raise Lisp::Error, I18n.t("tablero.errores.titulo") unless titulo.is_a?(String)
    raise Lisp::Error, I18n.t("tablero.errores.valor", titulo: titulo) unless valor.is_a?(Numeric) || valor.is_a?(String)
    formato ||= :number
    raise Lisp::Error, I18n.t("tablero.errores.formato", formatos: FORMATOS.join(" :")) unless FORMATOS.include?(formato)
    Pieza.new(tipo: :tile, titulo: titulo, valor: valor, formato: formato, panel: nil, limite: nil)
  end

  def self.panel(nombre, limite = 10)
    raise Lisp::Error, I18n.t("tablero.errores.panel", panel: nombre, paneles: PANELES.join(" :")) unless PANELES.include?(nombre)
    raise Lisp::Error, I18n.t("tablero.errores.limite") unless limite.is_a?(Integer) && limite.between?(1, 50)
    Pieza.new(tipo: :panel, titulo: nil, valor: nil, formato: nil, panel: nombre, limite: limite)
  end

  def self.comprobar_pieza!(pieza)
    raise Lisp::Error, I18n.t("tablero.errores.pieza", valor: Lisp.a_texto(pieza)) unless pieza.is_a?(Pieza)
  end

  private_class_method :tile, :panel, :comprobar_pieza!

  # Lo que el programa puede leer, calculado una sola vez y solo si lo pide. El dinero va en
  # pesos (BigDecimal), que es como se escribe en el programa.
  class Datos
    def initialize(sucursales:, desde:, hasta:, puede_revisar: false)
      @sucursales = sucursales
      @desde = desde
      @hasta = hasta
      @puede_revisar = puede_revisar
      @cache = {}
    end

    def ventas_del_rango = @ventas_del_rango ||= Venta.where(sucursal: @sucursales, fecha_negocio: @desde..@hasta)

    def ventas = pesos(:ventas) { ventas_del_rango.sum(:total_centavos) }
    def tickets = @cache[:tickets] ||= ventas_del_rango.count
    def ticket_promedio = tickets.zero? ? BigDecimal("0") : (ventas / tickets).round(2)
    def devoluciones = pesos(:devoluciones) { Devolucion.where(venta: ventas_del_rango).sum(:total_centavos) }
    def efectivo = pesos(:efectivo) { por_forma.fetch("efectivo", 0) - ventas_del_rango.sum(:cambio_centavos) }
    def transferencias = pesos(:transferencias) { por_forma.fetch("transferencia", 0) }
    def depositos = pesos(:depositos) { por_forma.fetch("deposito", 0) }
    def valor_existencias = pesos(:existencias) { Existencia.where(sucursal: @sucursales).joins(:producto).sum("existencias.cantidad * productos.precio_centavos").to_i }
    def por_pagar = pesos(:por_pagar) { Modulo.activo?("compras") ? MovimientoProveedor.sum(:delta_centavos) : 0 }
    def por_revisar = @cache[:por_revisar] ||= (@puede_revisar ? Revision.pendientes.where(sucursal: @sucursales).count : 0)
    def dias = (@hasta - @desde).to_i + 1

    def vendido(clave) = lineas_de(clave).sum(:cantidad).then { |c| BigDecimal(c.to_s) }
    def vendido_importe(clave) = BigDecimal(lineas_de(clave).sum(:importe_centavos)) / 100

    private

    def por_forma = @cache[:por_forma] ||= Pago.where(venta: ventas_del_rango).group(:forma).sum(:monto_centavos)

    def pesos(clave) = @cache[clave] ||= BigDecimal(yield.to_i) / 100

    def lineas_de(clave)
      raise Lisp::Error, I18n.t("tablero.errores.clave") unless clave.is_a?(String)
      producto = Producto.find_by(clave: clave.upcase) or raise Lisp::Error, I18n.t("tablero.errores.producto", clave: clave.upcase)
      VentaLinea.where(venta: ventas_del_rango, producto: producto)
    end
  end

  # Datos de prueba para la vista previa: cifras inventadas pero creíbles, para ver el tablero
  # lleno aunque hoy no haya ventas. No toca la base; los productos que se nombren sí tienen que
  # existir, para que un error de dedo se note igual que con los datos de verdad.
  class Muestra
    def initialize(desde:, hasta:)
      @desde = desde
      @hasta = hasta
    end

    def ventas = BigDecimal("18450.50") * dias
    def tickets = 137 * dias
    def ticket_promedio = (ventas / tickets).round(2)
    def devoluciones = BigDecimal("320.00") * dias
    def efectivo = BigDecimal("11200.00") * dias
    def transferencias = BigDecimal("5430.50") * dias
    def depositos = BigDecimal("1500.00") * dias
    def valor_existencias = BigDecimal("245000.00")
    def por_pagar = BigDecimal("38900.00")
    def por_revisar = 3
    def dias = (@hasta - @desde).to_i + 1

    def vendido(clave) = BigDecimal((producto(clave).id * 7 % 40) + 5) * dias
    def vendido_importe(clave) = (vendido(clave) * BigDecimal(producto(clave).precio_centavos) / 100).round(2)

    private

    def producto(clave)
      raise Lisp::Error, I18n.t("tablero.errores.clave") unless clave.is_a?(String)
      Producto.find_by(clave: clave.upcase) or raise Lisp::Error, I18n.t("tablero.errores.producto", clave: clave.upcase)
    end
  end
end
