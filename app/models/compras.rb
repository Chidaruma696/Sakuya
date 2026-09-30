# Las operaciones de Compras, cada una en una transacción con el proveedor bloqueado: recibir,
# facturar, ligar, pagar, anular y cancelar. Aquí viven las reglas; los
# controladores solo llaman.
module Compras
  class Error < ArgumentError; end

  # --- recepción: entrada al inventario con proveedor. `clave` es la idempotencia del navegador:
  # si llega repetida se devuelve la misma recepción.
  def self.recibir!(sucursal:, proveedor:, usuario:, lineas:, remision: nil, factura: nil, notas: nil, fecha: Date.current, clave: nil)
    Recepcion.transaction do
      if clave.present? && (previa = Recepcion.find_by(sucursal: sucursal, clave: clave))
        return previa
      end
      raise Error, I18n.t("errores.compras.factura_de_otro") if factura && factura.proveedor_id != proveedor.id
      raise Error, I18n.t("errores.compras.factura_cancelada") if factura&.cancelada?
      limpias = lineas.map { |l| l.to_h.symbolize_keys }.reject { |l| l[:producto_id].blank? || BigDecimal(l[:cantidad].to_s.presence || "0") <= 0 }
      raise Error, I18n.t("errores.compras.sin_renglones") if limpias.empty?
      recepcion = Recepcion.create!(sucursal: sucursal, proveedor: proveedor, usuario: usuario, factura: factura, remision: remision.presence,
                                    notas: notas.presence, fecha: fecha, clave: clave.presence)
      limpias.each do |l|
        producto = Producto.activos.find(l[:producto_id])
        linea = recepcion.lineas.create!(producto: producto, cantidad: l[:cantidad], cajas: l[:cajas].to_i)
        Inventario.mover!(sucursal: sucursal, producto: producto, tipo: "entrada", cantidad: linea.cantidad, usuario: usuario, referencia: recepcion,
                          motivo: I18n.t("compras.avisos.entrada_motivo", folio: recepcion.folio, proveedor: proveedor.nombre), fecha: fecha)
      end
      recepcion
    end
  end

  # Cancelar una recepción: el inventario regresa (si la mercancía sigue ahí).
  def self.cancelar_recepcion!(recepcion, motivo:, usuario:)
    raise Error, I18n.t("errores.hace_falta_motivo") if motivo.blank?
    raise Error, I18n.t("errores.compras.recepcion_cancelada") unless recepcion.registrada?
    Recepcion.transaction do
      recepcion.lineas.includes(:producto).each do |l|
        Inventario.mover!(sucursal: recepcion.sucursal, producto: l.producto, tipo: "ajuste_salida", cantidad: l.cantidad, usuario: usuario,
                          referencia: recepcion, motivo: I18n.t("compras.avisos.cancelacion_motivo", folio: recepcion.folio, motivo: motivo))
      end
      recepcion.update!(estado: "cancelada", motivo_cancelacion: motivo, factura: nil)
    end
    recepcion
  end

  # --- factura: crea la deuda. Con renglones el monto se deriva; sin renglones se acepta el tecleado.
  def self.facturar!(proveedor:, sucursal:, usuario:, folio:, fecha:, lineas: [], monto_centavos: 0, vence: nil, concepto: nil)
    raise Error, I18n.t("errores.compras.folio_obligatorio") if folio.blank?
    limpias = lineas.map { |l| l.to_h.symbolize_keys }.reject { |l| l[:producto_id].blank? || BigDecimal(l[:cantidad].to_s.presence || "0") <= 0 }
    FacturaProveedor.transaction do
      proveedor.lock!
      raise Error, I18n.t("errores.compras.folio_repetido", folio: folio) if proveedor.facturas.exists?(folio: folio.strip)
      vence ||= (proveedor.dias_credito.positive? ? fecha + proveedor.dias_credito.days : nil)
      factura = proveedor.facturas.new(sucursal: sucursal, usuario: usuario, folio: folio.strip, fecha: fecha, vence: vence, concepto: concepto.presence, monto_centavos: 1)
      limpias.each do |l|
        factura.lineas.build(producto: Producto.find(l[:producto_id]), cantidad: l[:cantidad], cajas: l[:cajas].to_i, precio_centavos: Dinero.centavos(l[:precio]))
      end
      factura.monto_centavos = limpias.any? ? factura.lineas.sum { |x| Dinero.importe(x.cantidad, x.precio_centavos) } : monto_centavos.to_i
      raise Error, I18n.t("errores.compras.monto_cero") unless factura.monto_centavos.positive?
      factura.save!
      asentar!(proveedor, tipo: "cargo", monto: factura.monto_centavos, delta: factura.monto_centavos, sucursal: sucursal, usuario: usuario,
               factura: factura, fecha: fecha, concepto: I18n.t("compras.avisos.cargo_factura", folio: factura.folio))
      factura
    end
  end

  # Cancelar factura: solo sin pagos vigentes; la deuda se revierte con un ajuste y las recepciones quedan sueltas.
  def self.cancelar_factura!(factura, motivo:, usuario:)
    raise Error, I18n.t("errores.hace_falta_motivo") if motivo.blank?
    raise Error, I18n.t("errores.compras.factura_ya_cancelada") if factura.cancelada?
    raise Error, I18n.t("errores.compras.factura_con_pagos") if factura.pagos.vigentes.exists?
    FacturaProveedor.transaction do
      factura.proveedor.lock!
      factura.update!(estado: "cancelada", motivo_cancelacion: motivo)
      factura.recepciones.update_all(factura_proveedor_id: nil, updated_at: Time.current)
      asentar!(factura.proveedor, tipo: "ajuste", monto: factura.monto_centavos, delta: -factura.monto_centavos, sucursal: factura.sucursal, usuario: usuario,
               factura: factura, concepto: I18n.t("compras.avisos.cancelacion_factura", folio: factura.folio, motivo: motivo))
    end
    factura
  end

  def self.ligar!(recepcion, factura)
    raise Error, I18n.t("errores.compras.recepcion_cancelada") unless recepcion.registrada?
    if factura
      raise Error, I18n.t("errores.compras.factura_de_otro") if factura.proveedor_id != recepcion.proveedor_id
      raise Error, I18n.t("errores.compras.factura_cancelada") if factura.cancelada?
    end
    recepcion.update!(factura: factura)
  end

  # --- pago: un solo camino. Efectivo sale de la gaveta abierta; ligado a factura no pasa de lo que resta.
  def self.pagar!(proveedor:, sucursal:, usuario:, monto_centavos:, forma: "efectivo", factura: nil, referencia: nil)
    monto = monto_centavos.to_i
    raise Error, I18n.t("errores.compras.monto_cero") unless monto.positive?
    raise Error, I18n.t("errores.caja.forma_desconocida", forma: forma) unless Pago::FORMAS.include?(forma)
    PagoProveedor.transaction do
      proveedor.lock!
      if factura
        raise Error, I18n.t("errores.compras.factura_de_otro") if factura.proveedor_id != proveedor.id
        raise Error, I18n.t("errores.compras.factura_cancelada") if factura.cancelada?
        raise Error, I18n.t("errores.compras.pago_excede", resta: Dinero.pesos(factura.resta_centavos)) if monto > factura.resta_centavos
      elsif monto > proveedor.saldo_centavos
        raise Error, I18n.t("errores.compras.anticipo_excede", saldo: Dinero.pesos(proveedor.saldo_centavos))
      end
      corte = retiro = nil
      if forma == "efectivo"
        corte = Corte.abierto_en(sucursal) or raise Error, I18n.t("errores.caja.sin_caja_en", sucursal: sucursal.nombre)
        retiro = corte.retirar!(monto_centavos: monto, motivo: I18n.t("compras.avisos.retiro_pago", proveedor: proveedor.nombre, folio: factura&.folio), usuario: usuario, autorizado_por: usuario)
      end
      pago = proveedor.pagos.create!(factura: factura, sucursal: sucursal, corte: corte, retiro: retiro, usuario: usuario, monto_centavos: monto, forma: forma, referencia: referencia.presence)
      asentar!(proveedor, tipo: "abono", monto: monto, delta: -monto, sucursal: sucursal, usuario: usuario, factura: factura, pago: pago,
               concepto: I18n.t("compras.avisos.abono_pago", folio: factura&.folio || "—", forma: I18n.t("formas_pago.#{forma}")))
      pago
    end
  end

  # Anular un pago compensa el abono; el efectivo solo regresa a la gaveta si el corte sigue abierto.
  def self.anular_pago!(pago, motivo:, usuario:)
    raise Error, I18n.t("errores.hace_falta_motivo") if motivo.blank?
    raise Error, I18n.t("errores.compras.pago_ya_anulado") unless pago.vigente?
    PagoProveedor.transaction do
      pago.proveedor.lock!
      retiro = pago.retiro
      raise Error, I18n.t("errores.compras.corte_cerrado") if retiro && !Corte.abiertos.exists?(id: pago.corte_id)
      pago.update!(estado: "anulado", motivo_anulacion: motivo, anulado_por: usuario, retiro: nil)
      retiro&.destroy!
      asentar!(pago.proveedor, tipo: "ajuste", monto: pago.monto_centavos, delta: pago.monto_centavos, sucursal: pago.sucursal, usuario: usuario,
               factura: pago.factura, pago: pago, concepto: I18n.t("compras.avisos.anulacion_pago", motivo: motivo))
    end
    pago
  end

  # --- comparativo facturado vs recibido, por producto. Un reporte, no un candado.
  Comparado = Struct.new(:producto, :facturado, :recibido, keyword_init: true) do
    def diferencia = recibido - facturado
    def estado
      return "cuadra" if diferencia.abs <= BigDecimal("0.005")
      return "sin_recibir" if recibido.zero?
      return "sin_facturar" if facturado.zero?
      diferencia.negative? ? "faltante" : "sobrante"
    end
  end

  # Renglones que facturan más de lo que traen las recepciones que se van a ligar (antes de guardar).
  # lineas: [{ producto_id:, cantidad:, precio: }]; devuelve Comparado solo de lo que se pasa.
  def self.excedente(lineas, recepciones)
    facturado = lineas.group_by { |l| l[:producto_id].to_i }.transform_values { |ls| ls.sum { |l| BigDecimal(l[:cantidad].to_s) } }
    recibido = RecepcionLinea.where(recepcion: recepciones).group(:producto_id).sum(:cantidad)
    facturado.filter_map do |producto_id, cant|
      rec = recibido[producto_id] || 0
      Comparado.new(producto: Producto.find(producto_id), facturado: cant, recibido: rec) if cant - rec > BigDecimal("0.005")
    end
  end

  def self.comparativo(factura)
    facturado = factura.lineas.includes(:producto).group_by(&:producto).transform_values { |ls| ls.sum(&:cantidad) }
    recibido = RecepcionLinea.joins(:recepcion).where(recepciones: { factura_proveedor_id: factura.id, estado: "registrada" }).includes(:producto)
                             .group_by(&:producto).transform_values { |ls| ls.sum(&:cantidad) }
    (facturado.keys | recibido.keys).sort_by(&:nombre).map { |p| Comparado.new(producto: p, facturado: facturado[p] || 0, recibido: recibido[p] || 0) }
  end

  def self.asentar!(proveedor, tipo:, monto:, delta:, sucursal:, usuario:, concepto:, factura: nil, pago: nil, fecha: Date.current)
    saldo = proveedor.movimientos.sum(:delta_centavos) + delta
    proveedor.movimientos.create!(tipo: tipo, monto_centavos: monto, delta_centavos: delta, saldo_centavos: saldo, sucursal: sucursal, usuario: usuario,
                                  factura: factura, pago: pago, fecha: fecha, concepto: concepto)
  end
  private_class_method :asentar!
end
