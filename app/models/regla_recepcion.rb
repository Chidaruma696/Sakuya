# El gancho al recibir mercancía del proveedor: antes de que entre al inventario, una regla en el
# Lisp de Sakuya mira qué llega, de quién y con qué papeles, y decide.
#
# Contrato v1. Recibe (supplier) el nombre del proveedor, (lines) cuántos renglones, (products) la
# lista de claves, (quantity-of "CLAVE") cuánto llega de ese producto, (value) lo que vale a precio
# de catálogo, en pesos, (remission) la remisión escrita ("" si no hay), (invoiced) si va ligada a
# una factura y (authorized), verdadero si quien recibe tiene compras.forzar_recepcion. Devuelve
# (allow), (to-review motivo) o (reject motivo).
module ReglaRecepcion
  VERSION = 1

  DE_FABRICA = <<~LISP
    ; Goods arriving from a supplier, right before they enter the stock.
    ; Answer (allow), (to-review "why") or (reject "why").
    ; Out of the box nothing stops a receipt.
    (allow)
  LISP

  MOTIVOS = %i[].freeze
  FUNCIONES = %w[supplier lines products quantity-of value remission invoiced authorized].freeze
  EJEMPLO = <<~LISP
    (cond ((= (remission) "") (reject "No delivery note, no goods"))
          ((> (value) 50000) (to-review "Big delivery"))
          (else (allow)))
  LISP

  extend Gancho

  CASO = "reglas/caso_recepcion".freeze # el caso de prueba del editor

  # renglones: [{ producto:, cantidad: }]
  Datos = Data.define(:proveedor, :renglones, :valor, :remision, :facturada, :autorizado)

  def self.decidir(datos, codigo: Regla.vigente("recepcion")&.codigo)
    decidir_con(codigo, datos)
  end

  # lineas como llegan del formulario: [{ producto_id:, cantidad: }]
  def self.datos(sucursal:, proveedor:, lineas:, remision:, facturada:, autorizado:)
    renglones = lineas.map { |l| l.to_h.symbolize_keys }.reject { |l| l[:producto_id].blank? || BigDecimal(l[:cantidad].to_s.presence || "0") <= 0 }
                      .map { |l| { producto: Producto.activos.find(l[:producto_id]), cantidad: BigDecimal(l[:cantidad].to_s) } }
    valor = renglones.sum { |r| Revision.valor(r[:cantidad], r[:producto], sucursal) }
    Datos.new(proveedor: proveedor.nombre, renglones: renglones, valor: valor, remision: remision.to_s.strip, facturada: facturada, autorizado: autorizado)
  end

  # El caso de prueba del editor: claves con cantidades ("CATS 10, PECH 2.5"), remisión y si va
  # con factura. El valor sale del catálogo de la sucursal.
  def self.caso(params, sucursal)
    texto = params[:llegan].presence || Producto.activos.order(:nombre).limit(2).pluck(:clave).map { |c| "#{c} 10" }.join(", ")
    { llegan: texto, remision: params.key?(:remision) ? params[:remision].to_s : "R-123", facturada: params[:facturada] == "1",
      autorizado: params[:autorizado] == "1", sucursal: sucursal }
  end

  def self.probar(codigo, caso)
    lineas = caso[:llegan].split(",").map(&:split).reject(&:empty?).map do |clave, cantidad|
      producto = Producto.activos.find_by(clave: clave.upcase) or raise Lisp::Error, I18n.t("tablero.errores.producto", clave: clave.upcase)
      { producto_id: producto.id, cantidad: cantidad.presence || "1" }
    end
    evaluar(codigo, datos(sucursal: caso[:sucursal], proveedor: Proveedor.new(nombre: ""), lineas: lineas, remision: caso[:remision], facturada: caso[:facturada], autorizado: caso[:autorizado]))
  end

  def self.textos = "regla_recepcion"

  def self.interpolar(_datos) = {}

  def self.funciones(datos)
    {
      "supplier" => -> { datos.proveedor },
      "lines" => -> { datos.renglones.size },
      "products" => -> { datos.renglones.map { |r| r[:producto].clave }.uniq },
      "quantity-of" => ->(clave) { datos.renglones.select { |r| r[:producto].clave == clave.to_s.upcase }.sum(BigDecimal("0")) { |r| r[:cantidad] } },
      "value" => -> { BigDecimal(datos.valor) / 100 },
      "remission" => -> { datos.remision },
      "invoiced" => -> { datos.facturada },
      "authorized" => -> { datos.autorizado }
    }
  end

  private_class_method :funciones, :interpolar, :textos
end
