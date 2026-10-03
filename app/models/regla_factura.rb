# El gancho de las facturas de proveedor: antes de crear la deuda, una regla en el Lisp de Sakuya
# compara lo facturado con lo recibido en las recepciones que se ligan, y decide.
#
# Contrato v1. Recibe (excess-items) cuántos productos vienen de más, (excess-value) lo que vale
# lo de más a precio de la factura, en pesos, (total) el total de la factura, (receipts) cuántas
# recepciones se ligan, (supplier) el nombre del proveedor, (lock) si el candado de Ajustes ›
# Compras está puesto y (authorized), verdadero si quien factura tiene compras.exceder. Devuelve
# (allow), (to-review motivo) o (reject motivo).
module ReglaFactura
  VERSION = 1

  DE_FABRICA = <<~LISP
    ; A supplier invoice, compared with the receipts it is linked to.
    ; Answer (allow), (to-review "why") or (reject "why").
    ; With the lock from Settings › Purchases, invoicing more than was received stops.
    (if (or (not (lock)) (= (excess-items) 0))
        (allow)
        (reject :over-received))
  LISP

  MOTIVOS = %i[over-received].freeze
  FUNCIONES = %w[excess-items excess-value total receipts supplier lock authorized].freeze
  EJEMPLO = <<~LISP
    (cond ((= (excess-items) 0) (allow))
          ((<= (excess-value) 100) (to-review "Small excess"))
          (else (reject :over-received)))
  LISP

  extend Gancho

  CASO = "reglas/caso_factura".freeze # el caso de prueba del editor

  Datos = Data.define(:productos_de_mas, :valor_de_mas, :total, :recepciones, :proveedor, :candado, :autorizado, :detalle)

  def self.decidir(datos, codigo: Regla.vigente("factura")&.codigo)
    decidir_con(codigo, datos)
  end

  def self.candado? = Ajuste["compras.candado_recibido"] == "1"

  # El caso de prueba del editor: cuántos productos de más, cuánto valen, el total y si factura
  # alguien con permiso. El candado es el de Ajustes › Compras.
  def self.caso(params, _sucursal)
    folio = params[:factura].to_s.strip.presence
    { productos_de_mas: params[:productos_de_mas].presence&.to_i || 1, valor_de_mas: params[:valor_de_mas].present? ? Dinero.centavos(params[:valor_de_mas]) : 15_000,
      total: params[:total].present? ? Dinero.centavos(params[:total]) : 450_000, autorizado: params[:autorizado] == "1",
      folio_factura: folio, factura: (FacturaProveedor.where(folio: folio).order(id: :desc).first if folio) }
  end

  # Con una factura de verdad, la compara con las recepciones que tiene ligadas, como al registrarla.
  def self.probar(codigo, caso)
    raise Lisp::Error, I18n.t("regla_factura.factura_no_existe", folio: caso[:folio_factura]) if caso[:folio_factura] && !caso[:factura]
    return evaluar(codigo, datos_de(caso[:factura], caso[:autorizado])) if caso[:factura]
    evaluar(codigo, Datos.new(productos_de_mas: caso[:productos_de_mas], valor_de_mas: caso[:valor_de_mas], total: caso[:total], recepciones: 1,
                              proveedor: "", candado: candado?, autorizado: caso[:autorizado], detalle: ""))
  end

  def self.datos_de(factura, autorizado)
    lineas = factura.lineas.map { |l| { producto_id: l.producto_id, cantidad: l.cantidad } }
    exceso = Compras.excedente(lineas, factura.recepciones.to_a)
    valor = exceso.sum { |c| Dinero.importe(-c.diferencia, factura.lineas.select { |l| l.producto_id == c.producto.id }.map(&:precio_centavos).max.to_i) }
    Datos.new(productos_de_mas: exceso.size, valor_de_mas: valor, total: factura.monto_centavos, recepciones: factura.recepciones.size,
              proveedor: factura.proveedor.nombre, candado: candado?, autorizado: autorizado, detalle: exceso.map { |c| c.producto.nombre }.join(", "))
  end

  def self.textos = "regla_factura"

  def self.interpolar(datos) = { detalle: datos.detalle }

  def self.funciones(datos)
    {
      "excess-items" => -> { datos.productos_de_mas },
      "excess-value" => -> { BigDecimal(datos.valor_de_mas) / 100 },
      "total" => -> { BigDecimal(datos.total) / 100 },
      "receipts" => -> { datos.recepciones },
      "supplier" => -> { datos.proveedor },
      "lock" => -> { datos.candado },
      "authorized" => -> { datos.autorizado }
    }
  end

  private_class_method :funciones, :interpolar, :textos, :datos_de
end
