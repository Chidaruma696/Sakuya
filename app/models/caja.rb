# La única puerta para cobrar y para devolver. Todo en una transacción: venta, líneas, pagos
# y kardex; si algo falla, no queda nada a medias.
module Caja
  class Error < StandardError; end

  # lineas: [{ producto_id:, cantidad:, precio_centavos: }]
  # pagos:  [{ forma:, monto_centavos: }]
  # clave:  identificador único del ticket generado por la caja; repetir la misma clave devuelve la misma venta.
  def self.cobrar!(sucursal:, usuario:, lineas:, pagos:, clave:, autorizador: nil)
    raise Error, I18n.t("errores.caja.clave_ticket") if clave.blank?
    if (previa = Venta.find_by(clave: clave))
      return previa
    end
    corte = Corte.abierto_en(sucursal) or raise Error, I18n.t("errores.caja.sin_caja", sucursal: sucursal.nombre)
    raise Error, I18n.t("errores.caja.excede_limite", monto: Dinero.pesos(sucursal.limite_efectivo_centavos)) if corte.excede_limite?
    raise Error, I18n.t("errores.caja.ticket_vacio") if lineas.blank?

    Venta.transaction do
      preparadas = lineas.map { |l| preparar_linea(sucursal, l, autorizador) }
      total = preparadas.sum { |l| l[:importe_centavos] }
      pagos_ok = preparar_pagos(pagos, total)
      cambio = pagos_ok.sum { |p| p[:monto_centavos] } - total

      venta = Venta.create!(sucursal: sucursal, corte: corte, usuario: usuario, clave: clave,
                            folio: Folio.siguiente!(sucursal, "venta"), codigo: codigo_ticket(sucursal),
                            total_centavos: total, cambio_centavos: cambio, fecha_negocio: Date.current)
      preparadas.each do |l|
        linea = venta.lineas.create!(l)
        Inventario.mover!(sucursal: sucursal, producto: linea.producto, tipo: "venta", cantidad: linea.cantidad,
                          usuario: usuario, referencia: venta, motivo: venta.folio)
      end
      pagos_ok.each { |p| venta.pagos.create!(p) }
      venta
    end
  rescue Inventario::SinExistencia => e
    raise Error, I18n.t("errores.caja.no_se_vende_sin", mensaje: e.message)
  end

  # lineas: [{ venta_linea_id:, cantidad: }]. El dinero sale de la gaveta del corte abierto.
  def self.devolver!(venta:, lineas:, motivo:, usuario:)
    raise Error, I18n.t("errores.hace_falta_motivo") if motivo.blank?
    raise Error, I18n.t("errores.caja.ya_devuelta") unless venta.cobrada?
    corte = Corte.abierto_en(venta.sucursal) or raise Error, I18n.t("errores.caja.sin_caja_devolver")
    raise Error, I18n.t("errores.caja.nada_devuelto") if lineas.blank?

    Venta.transaction do
      devolucion = Devolucion.new(venta: venta, corte: corte, usuario: usuario, motivo: motivo, total_centavos: 0)
      total = 0
      lineas.each do |l|
        vl = venta.lineas.find(l[:venta_linea_id])
        cantidad = BigDecimal(l[:cantidad].to_s).round(3)
        raise Error, I18n.t("errores.caja.max_devolver", producto: vl.producto.nombre, max: vl.cantidad_pendiente.to_s("F")) if cantidad <= 0 || cantidad > vl.cantidad_pendiente
        importe = Dinero.importe(cantidad, vl.precio_centavos)
        total += importe
        devolucion.lineas.build(venta_linea: vl, cantidad: cantidad, importe_centavos: importe)
        Inventario.mover!(sucursal: venta.sucursal, producto: vl.producto, tipo: "devolucion_cliente", cantidad: cantidad,
                          usuario: usuario, referencia: devolucion, motivo: "#{venta.folio}: #{motivo}")
      end
      devolucion.total_centavos = total
      devolucion.save!
      venta.update!(estado: "devuelta") if venta.lineas.all? { |vl| vl.reload.cantidad_pendiente.zero? }
      devolucion
    end
  end

  def self.preparar_linea(sucursal, l, autorizador)
    producto = Producto.activos.find(l[:producto_id])
    cantidad = BigDecimal(l[:cantidad].to_s).round(3)
    raise Error, I18n.t("errores.caja.cantidad_invalida", producto: producto.nombre) unless cantidad.positive?
    raise Error, I18n.t("errores.caja.piezas_enteras", producto: producto.nombre) if !producto.fraccionable? && cantidad != cantidad.floor
    catalogo = producto.precio_centavos_en(sucursal)
    # Un producto nuevo llega a la tienda sin precio: se recibe, pero no se vende hasta que lo tenga.
    raise Error, I18n.t("errores.caja.sin_precio", producto: producto.nombre, sucursal: sucursal.nombre) unless catalogo.positive?
    promo_precio, promocion = Promocion.mejor(producto, sucursal, cantidad, catalogo)
    legitimo = promo_precio || catalogo
    precio = l[:precio_centavos].present? ? l[:precio_centavos].to_i : legitimo
    # Bajar el precio: nunca por debajo del piso; a nombre de quien tiene el permiso, o sin nadie
    # (y entonces el controlador lo deja por revisar).
    autoriza = nil
    if precio < legitimo
      piso = Ajuste.entero("caja.piso_precio") / 100.0 # nunca por debajo del piso, ni con permiso
      raise Error, I18n.t("errores.caja.piso_precio", producto: producto.nombre, piso: Ajuste.entero("caja.piso_precio"), monto: Dinero.pesos((catalogo * piso).ceil)) if precio < catalogo * piso
      autoriza = autorizador if autorizador&.puede?("caja.bajar_precio")
    end
    { producto: producto, cantidad: cantidad, precio_centavos: precio, catalogo_centavos: catalogo,
      importe_centavos: Dinero.importe(cantidad, precio), autorizado_por: autoriza, promocion: (precio == promo_precio ? promocion : nil) }
  end
  private_class_method :preparar_linea

  def self.preparar_pagos(pagos, total)
    limpios = Array(pagos).map { |p| { forma: p[:forma].to_s, monto_centavos: p[:monto_centavos].to_i } }.reject { |p| p[:monto_centavos] <= 0 }
    limpios.each { |p| raise Error, I18n.t("errores.caja.forma_desconocida", forma: p[:forma]) unless Pago::FORMAS.include?(p[:forma]) }
    suma = limpios.sum { |p| p[:monto_centavos] }
    raise Error, I18n.t("errores.caja.falta_dinero", total: Dinero.pesos(total), pago: Dinero.pesos(suma)) if suma < total
    no_efectivo = limpios.reject { |p| p[:forma] == "efectivo" }.sum { |p| p[:monto_centavos] }
    raise Error, I18n.t("errores.caja.no_efectivo_excede") if no_efectivo > total
    limpios
  end
  private_class_method :preparar_pagos

  def self.codigo_ticket(sucursal)
    secuencia = Contador.siguiente!("ticket:#{sucursal.id}")
    Barcode.ean13(format("09%02d%08d", sucursal.id % 100, secuencia % 100_000_000))
  end
  private_class_method :codigo_ticket
end
