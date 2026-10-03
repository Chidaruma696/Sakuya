# La única puerta para cobrar y para devolver. Todo en una transacción: venta, líneas, pagos
# y kardex; si algo falla, no queda nada a medias.
module Caja
  class Error < StandardError; end

  # La regla del precio frenó un renglón: no se cobra nada y el intento queda reportado.
  class Frenado < Error
    attr_reader :reporte, :valor_centavos

    def initialize(mensaje, reporte:, valor_centavos:)
      super(mensaje)
      @reporte = reporte
      @valor_centavos = valor_centavos
    end
  end

  # lineas: [{ producto_id:, cantidad:, precio_centavos: }]
  # pagos:  [{ forma:, monto_centavos: }]; la forma "credito" va a cuenta del cliente.
  # clave:  identificador único del ticket generado por la caja; repetir la misma clave devuelve la misma venta.
  # cliente: a quién se le vende (hace falta para vender a cuenta).
  def self.cobrar!(sucursal:, usuario:, lineas:, pagos:, clave:, autorizador: nil, cliente: nil)
    raise Error, I18n.t("errores.caja.clave_ticket") if clave.blank?
    if (previa = Venta.find_by(clave: clave))
      return previa
    end
    corte = Corte.abierto_en(sucursal) or raise Error, I18n.t("errores.caja.sin_caja", sucursal: sucursal.nombre)
    raise Error, I18n.t("errores.caja.excede_limite", monto: Dinero.pesos(sucursal.limite_efectivo_centavos)) if corte.excede_limite?
    raise Error, I18n.t("errores.caja.ticket_vacio") if lineas.blank?

    codigo = Regla.vigente("precio")&.codigo
    fallos = [] # [clave del texto, error] de las reglas que tronaron

    Venta.transaction do
      preparadas = lineas.map { |l| preparar_linea(sucursal, l, autorizador, codigo, fallos) }
      total = preparadas.sum { |l| l[:importe_centavos] }
      pagos_ok = preparar_pagos(pagos, total)
      cambio = pagos_ok.sum { |p| p[:monto_centavos] } - total
      a_cuenta = pagos_ok.select { |p| p[:forma] == Pago::A_CUENTA }.sum { |p| p[:monto_centavos] }
      revisar_venta = juzgar_venta!(preparadas, pagos_ok, total, cambio, usuario, fallos)
      revisar_credito = juzgar_credito!(cliente, a_cuenta, total, usuario, fallos) if a_cuenta.positive?

      venta = Venta.create!(sucursal: sucursal, corte: corte, usuario: usuario, clave: clave, cliente: cliente,
                            folio: Folio.siguiente!(sucursal, "venta"), codigo: codigo_ticket(sucursal),
                            total_centavos: total, cambio_centavos: cambio, fecha_negocio: Date.current)
      preparadas.each do |l|
        revisar, valor = l.extract!(:revisar, :valor_revision).values_at(:revisar, :valor_revision)
        linea = venta.lineas.create!(l)
        Inventario.mover!(sucursal: sucursal, producto: linea.producto, tipo: "venta", cantidad: linea.cantidad,
                          usuario: usuario, referencia: venta, motivo: venta.folio)
        Revision.abrir!(linea, usuario: usuario, sucursal: sucursal, motivo: revisar, valor_centavos: valor) if revisar
      end
      pagos_ok.each { |p| venta.pagos.create!(p) }
      Revision.abrir!(venta, usuario: usuario, sucursal: sucursal, motivo: revisar_venta, valor_centavos: total) if revisar_venta
      if a_cuenta.positive?
        cliente.movimientos_credito.create!(tipo: "cargo", monto_centavos: a_cuenta, fecha: Date.current, referencia: venta, sucursal: sucursal,
                                            usuario: usuario, motivo: I18n.t("clientes.cuenta.cargo_venta", folio: venta.folio))
        Revision.abrir!(venta, usuario: usuario, sucursal: sucursal, motivo: revisar_credito, valor_centavos: a_cuenta) if revisar_credito
      end
      # Si la regla del negocio tronó decidió la de fábrica; el fallo se reporta una vez por corte.
      fallos.uniq.each { |clave, f| Revision.abrir!(corte, usuario: usuario, sucursal: sucursal, motivo: I18n.t(clave, error: f), sin_repetir: true) }
      venta
    end
  rescue Inventario::SinExistencia => e
    raise Error, I18n.t("errores.caja.no_se_vende_sin", mensaje: e.message)
  rescue Frenado => e
    Revision.abrir!(corte, usuario: usuario, sucursal: sucursal, motivo: e.reporte, valor_centavos: e.valor_centavos, frenado: true)
    raise
  end

  # lineas: [{ venta_linea_id:, cantidad: }]. El dinero sale de la gaveta del corte abierto; si la
  # venta fue a cuenta, primero baja lo que el cliente debe de ella y solo lo demás sale en efectivo.
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
      devolucion.a_cuenta_centavos = [ total, venta.a_cuenta_pendiente_centavos ].min if venta.cliente
      devolucion.save!
      if devolucion.a_cuenta_centavos.positive?
        venta.cliente.movimientos_credito.create!(tipo: "devolucion", monto_centavos: -devolucion.a_cuenta_centavos, fecha: Date.current, referencia: devolucion,
                                                  sucursal: venta.sucursal, usuario: usuario, motivo: I18n.t("clientes.cuenta.devolucion", folio: venta.folio))
      end
      venta.update!(estado: "devuelta") if venta.lineas.all? { |vl| vl.reload.cantidad_pendiente.zero? }
      devolucion
    end
  end

  def self.preparar_linea(sucursal, l, autorizador, codigo, fallos)
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
    if precio < legitimo
      piso = Ajuste.entero("caja.piso_precio") / 100.0 # nunca por debajo del piso, ni con permiso ni con regla
      raise Error, I18n.t("errores.caja.piso_precio", producto: producto.nombre, piso: Ajuste.entero("caja.piso_precio"), monto: Dinero.pesos((catalogo * piso).ceil)) if precio < catalogo * piso
    end
    # Lo demás lo decide la regla del precio. Si frena y quien autoriza tiene caja.bajar_precio,
    # pasa a su nombre pero queda por revisar: nadie se queda sin poder vender.
    autorizado = autorizador&.puede?("caja.bajar_precio") || false
    datos = ReglaPrecio::Datos.new(producto: producto, cantidad: cantidad, precio: precio, catalogo: catalogo, regular: legitimo, autorizado: autorizado)
    decision = ReglaPrecio.decidir(datos, codigo: codigo)
    fallos << [ "regla_precio.fallo", decision.error ] if decision.error
    cobro = I18n.t("caja.cobro", producto: producto.nombre, precio: Dinero.pesos(precio), regular: Dinero.pesos(legitimo))
    valor = Dinero.importe(cantidad, [ legitimo - precio, 0 ].max)
    if decision.rechaza? && !autorizado
      raise Frenado.new(I18n.t("errores.caja.precio_frenado", cobro: cobro, motivo: decision.motivo), reporte: "#{cobro}: #{decision.motivo}", valor_centavos: valor)
    end
    { producto: producto, cantidad: cantidad, precio_centavos: precio, catalogo_centavos: catalogo,
      importe_centavos: Dinero.importe(cantidad, precio), autorizado_por: (autorizador if autorizado && precio < legitimo),
      promocion: (precio == promo_precio ? promocion : nil),
      revisar: (decision.permite? ? nil : "#{cobro}: #{decision.motivo}"), valor_revision: valor }
  end
  private_class_method :preparar_linea

  # La venta entera, antes de cobrarla, por la regla de ventas. Si frena y quien cobra no tiene
  # caja.forzar_venta, no se cobra y queda reportado; si no, devuelve el motivo para revisarla (o nil).
  def self.juzgar_venta!(preparadas, pagos, total, cambio, usuario, fallos)
    autorizado = usuario.puede?("caja.forzar_venta")
    datos = ReglaVenta.datos(preparadas, pagos, total: total, cambio: cambio, autorizado: autorizado)
    decision = ReglaVenta.decidir(datos, codigo: Regla.vigente("venta")&.codigo)
    fallos << [ "regla_venta.fallo", decision.error ] if decision.error
    if decision.rechaza? && !autorizado
      raise Frenado.new(I18n.t("errores.caja.venta_frenada", motivo: decision.motivo), reporte: I18n.t("caja.venta_frenada", total: Dinero.pesos(total), motivo: decision.motivo), valor_centavos: total)
    end
    decision.permite? ? nil : decision.motivo
  end
  private_class_method :juzgar_venta!

  # A cuenta del cliente, si la regla de crédito lo deja. Si frena y quien cobra no tiene
  # clientes.forzar_credito, no se cobra y queda reportado; si no, devuelve el motivo para revisarla (o nil).
  def self.juzgar_credito!(cliente, a_cuenta, total, usuario, fallos)
    raise Error, I18n.t("errores.caja.a_cuenta_sin_cliente") unless cliente
    autorizado = usuario.puede?("clientes.forzar_credito")
    decision = ReglaCredito.decidir(ReglaCredito.datos(cliente, monto: a_cuenta, total: total, autorizado: autorizado))
    fallos << [ "regla_credito.fallo", decision.error ] if decision.error
    if decision.rechaza? && !autorizado
      raise Frenado.new(I18n.t("errores.caja.credito_frenado", motivo: decision.motivo),
                        reporte: I18n.t("caja.credito_frenado", cliente: cliente.nombre, monto: Dinero.pesos(a_cuenta), motivo: decision.motivo), valor_centavos: a_cuenta)
    end
    decision.permite? ? nil : decision.motivo
  end
  private_class_method :juzgar_credito!

  def self.preparar_pagos(pagos, total)
    limpios = Array(pagos).map { |p| { forma: p[:forma].to_s, monto_centavos: p[:monto_centavos].to_i } }.reject { |p| p[:monto_centavos] <= 0 }
    limpios.each { |p| raise Error, I18n.t("errores.caja.forma_desconocida", forma: p[:forma]) unless (Pago::FORMAS + [ Pago::A_CUENTA ]).include?(p[:forma]) }
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
