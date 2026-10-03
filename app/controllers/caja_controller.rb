class CajaController < ApplicationController
  pestana :caja

  before_action :cargar_corte

  # ---- vender
  # Con ?pedido=ID, el ticket llega armado con lo del pedido y su cliente.
  def index
    autorizar!("caja.vender")
    @clave = SecureRandom.uuid
    return unless params[:pedido].present? && Modulo.activo?("clientes")
    @pedido = Pedido.abiertos.where(sucursal: sucursal_actual).includes(lineas: :producto).find_by(id: params[:pedido])
    return unless @pedido
    @pedido_pos = { id: @pedido.id, folio: @pedido.folio, cliente_id: @pedido.cliente_id,
                    lineas: @pedido.lineas.filter_map { |l| datos_pos(l.producto)&.merge(cantidad: l.cantidad.to_f) } }
  end

  # Qué es lo que se escaneó o tecleó, para el ticket (JSON).
  def escanear
    autorizar!("caja.vender")
    r = Escaneo.resolver(params[:codigo])
    return render json: { error: "No se encontró «#{params[:codigo]}»" }, status: :not_found unless r
    datos = datos_pos(r.producto)
    return render json: { error: t("errores.caja.sin_precio", producto: r.producto.nombre, sucursal: sucursal_actual.nombre) }, status: :unprocessable_entity unless datos
    render json: datos
  end

  def cobrar
    autorizar!("caja.vender")
    lineas = JSON.parse(params[:lineas].to_s).map { |l| l.symbolize_keys.slice(:producto_id, :cantidad, :precio_centavos) }
    pagos = JSON.parse(params[:pagos].to_s).map(&:symbolize_keys)
    autoriza = autorizador_o_revision("caja.bajar_precio")
    # Los precios los juzga la regla del precio dentro de Caja: lo que frena no se cobra, y lo que
    # pide revisión se cobra y queda por revisar.
    cliente = Cliente.activos.find_by(id: params[:cliente_id]) if params[:cliente_id].present? && Modulo.activo?("clientes")
    pedido = Pedido.abiertos.where(sucursal: sucursal_actual).find_by(id: params[:pedido_id]) if params[:pedido_id].present?
    venta = Caja.cobrar!(sucursal: sucursal_actual, usuario: usuario_actual, lineas: lineas, pagos: pagos, clave: params[:clave], autorizador: autoriza, cliente: cliente, pedido: pedido)
    pedido&.entregar!(venta)
    render json: { url: caja_ticket_path(venta, imprimir: 1), folio: venta.folio, cambio: Dinero.pesos(venta.cambio_centavos) }
  rescue Caja::Error, JSON::ParserError, ActiveRecord::RecordNotFound, ActiveRecord::RecordInvalid => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def ventas
    autorizar!("caja.vender")
    @ventas = Venta.where(sucursal: sucursal_actual).includes(:usuario, :pagos, lineas: :producto).recientes.limit(100)
  end

  def ticket
    autorizar!("caja.vender")
    @venta = Venta.where(sucursal: sucursal_actual).includes(:pagos, :usuario, lineas: :producto).find(params[:id])
    @termica = { modo: sucursal_actual.impresora, escpos: caja_escpos_path(@venta), imprimir: caja_imprimir_path(@venta) }
    render layout: "ticket"
  end

  # El mismo ticket en bytes ESC/POS, para una impresora térmica.
  def escpos
    autorizar!("caja.vender")
    venta = Venta.where(sucursal: sucursal_actual).find(params[:id])
    send_data EscPos.ticket(venta), filename: "#{venta.folio}.bin", type: "application/octet-stream", disposition: params[:bajar] ? "attachment" : "inline"
  end

  # Imprime el ticket en la térmica de red de la sucursal (JSON: ok o el error).
  def imprimir
    autorizar!("caja.vender")
    imprimir_en_red(EscPos.ticket(Venta.where(sucursal: sucursal_actual).find(params[:id])))
  end

  # El resumen del corte en ESC/POS, y en la térmica de red.
  def resumen_escpos
    corte = corte_para_resumen
    send_data EscPos.resumen(corte), filename: "#{corte.folio}.bin", type: "application/octet-stream", disposition: params[:bajar] ? "attachment" : "inline"
  end

  def resumen_imprimir
    imprimir_en_red(EscPos.resumen(corte_para_resumen))
  end

  # ---- corte
  def corte
    autorizar!("caja.abrir")
    @cortes = Corte.where(sucursal: sucursal_actual).where(estado: "cerrado").includes(:usuario).order(cerrado_en: :desc).limit(15)
  end

  def abrir
    autorizar!("caja.abrir")
    Corte.abrir!(sucursal: sucursal_actual, usuario: usuario_actual, fondo_centavos: Dinero.centavos(params[:fondo]))
    redirect_to caja_path, notice: t("caja.avisos.abierta", fondo: Dinero.pesos(Dinero.centavos(params[:fondo])))
  rescue ArgumentError, ActiveRecord::RecordInvalid => e
    redirect_to caja_corte_path, alert: e.message
  end

  # Se cuenta por billetes y monedas (denominacion[centavos] = cuántos) o se teclea el total. La
  # diferencia la juzga la regla del corte (ReglaCorte): si pide revisión hace falta motivo, y si
  # rechaza no se cierra y el intento queda reportado, salvo que cierre alguien con caja.diferencia
  # (entonces queda por revisar).
  def cerrar
    autorizar!("caja.abrir")
    raise ArgumentError, t("errores.caja.sin_caja_simple") unless @corte
    desglose = params.fetch(:denominacion, {}).to_unsafe_h.select { |_, c| c.to_i.positive? }
    contado = desglose.any? ? Corte.sumar(desglose) : Dinero.centavos(params[:contado])
    diferencia = contado - @corte.efectivo_esperado_centavos
    decision = ReglaCorte.decidir(@corte, contado_centavos: contado, usuario: usuario_actual)
    if decision.rechaza? && !puede?("caja.diferencia")
      reportar_cierre_frenado(contado, diferencia, decision)
      raise ArgumentError, t("errores.corte.rechazado", motivo: decision.motivo)
    end
    autoriza = decision.permite? ? usuario_actual : nil
    raise ArgumentError, t("errores.corte.falta_motivo", motivo: decision.motivo) if autoriza.nil? && params[:motivo].blank?
    # Si la regla del negocio tronó decidió la de fábrica, y el fallo se asienta en la revisión del corte.
    motivo = [ params[:motivo], (t("regla_corte.fallo", error: decision.error) if decision.error) ].compact_blank.join("\n")
    autoriza = nil if decision.error
    @corte.cerrar!(contado_centavos: contado, usuario: usuario_actual, desglose: desglose)
    revisar_si_hace_falta(@corte, autoriza, motivo: motivo, valor_centavos: diferencia.abs)
    aviso = t("caja.avisos.corte_cerrado", folio: @corte.folio, esperado: Dinero.pesos(@corte.esperado_centavos), contado: Dinero.pesos(@corte.contado_centavos), diferencia: Dinero.pesos(@corte.diferencia_centavos))
    redirect_to caja_resumen_path(@corte), notice: aviso + (autoriza ? "" : t("caja.avisos.queda_por_revisar"))
  rescue ArgumentError, ActiveRecord::RecordInvalid => e
    redirect_to caja_corte_path, alert: e.message
  end

  # El resumen del día de un corte: lo que pasó por la caja y alrededor, en hoja de 80 mm para
  # imprimir o compartir. Sale solo al cerrar y queda en la lista de cortes.
  def resumen
    raise SinPermiso, "caja.abrir" unless puede?("caja.abrir") || puede?("reportes.ver")
    @c = Corte.where(sucursal: sucursal_actual).includes(:usuario, :cerrado_por, retiros: :usuario).find(params[:id])
    @termica = { modo: sucursal_actual.impresora, escpos: caja_resumen_escpos_path(@c), imprimir: caja_resumen_imprimir_path(@c) }
    ventas = @c.ventas_cobradas
    @tickets = ventas.count
    @total = ventas.sum(:total_centavos)
    @por_forma = Pago.where(venta: ventas).group(:forma).sum(:monto_centavos)
    @top = VentaLinea.where(venta: ventas).joins(:producto).group("productos.nombre", "productos.unidad")
                     .order(Arel.sql("SUM(importe_centavos) DESC")).limit(10).pluck("productos.nombre", "productos.unidad", Arel.sql("SUM(cantidad)"), Arel.sql("SUM(importe_centavos)"))
    ventana = @c.abierto_en..(@c.cerrado_en || Time.current)
    @revisiones = Revision.where(sucursal: sucursal_actual, created_at: ventana).includes(:usuario)
    @cargos = Cargo.where(sucursal: sucursal_actual, created_at: ventana).includes(:usuario)
    @titulo = "#{t("caja.resumen")} #{@c.folio}"
    render layout: "ticket"
  end

  # El retiro lo juzga la regla de retiros (ReglaRetiro): lo que frena no sale y queda reportado,
  # salvo que retire alguien con caja.retirar (entonces sale y queda por revisar).
  def retirar
    raise ArgumentError, t("errores.caja.sin_caja_simple") unless @corte
    monto = Dinero.centavos(params[:monto])
    @corte.comprobar_retiro!(monto, params[:motivo])
    decision = ReglaRetiro.decidir(@corte, monto_centavos: monto, motivo: params[:motivo], usuario: usuario_actual)
    con_permiso = puede?("caja.retirar")
    if decision.rechaza? && !con_permiso
      reporte = [ t("caja.retiro_frenado", monto: Dinero.pesos(monto), motivo: params[:motivo], regla: decision.motivo), (t("regla_retiro.fallo", error: decision.error) if decision.error) ].compact.join("\n")
      Revision.abrir!(@corte, usuario: usuario_actual, sucursal: sucursal_actual, motivo: reporte, valor_centavos: monto, frenado: true)
      raise ArgumentError, t("errores.caja.retiro_frenado", motivo: decision.motivo)
    end
    revisar = decision.permite? && !decision.error ? nil : [ params[:motivo], (decision.motivo unless decision.permite?), (t("regla_retiro.fallo", error: decision.error) if decision.error) ].compact.join("\n")
    retiro = @corte.retirar!(monto_centavos: monto, motivo: params[:motivo], usuario: usuario_actual, autorizado_por: (usuario_actual if con_permiso))
    Revision.abrir!(retiro, usuario: usuario_actual, sucursal: sucursal_actual, motivo: revisar, valor_centavos: retiro.monto_centavos) if revisar
    redirect_to caja_corte_path, notice: t("caja.avisos.retiro", monto: Dinero.pesos(retiro.monto_centavos)) + (revisar ? t("caja.avisos.queda_por_revisar") : "")
  rescue ArgumentError, ActiveRecord::RecordInvalid => e
    redirect_to caja_corte_path, alert: e.message
  end

  # ---- devoluciones: solo con ticket
  def devolucion
    autorizar!("caja.devolver")
    return if params[:codigo].blank?
    @venta = Venta.where(sucursal: sucursal_actual).then { |v| v.find_by(codigo: Barcode.variantes(params[:codigo])) || v.find_by(folio: params[:codigo].to_s.strip.upcase) }
    flash.now[:alert] = t("errores.caja.sin_ticket_devolucion", codigo: params[:codigo]) unless @venta
  end

  def devolver
    autorizar!("caja.devolver")
    venta = Venta.where(sucursal: sucursal_actual).find(params[:venta_id])
    lineas = params.fetch(:lineas, {}).to_unsafe_h.map { |id, cant| { venta_linea_id: id, cantidad: cant } }.reject { |l| l[:cantidad].blank? || l[:cantidad].to_d <= 0 }
    dev = Caja.devolver!(venta: venta, lineas: lineas, motivo: params[:motivo].to_s.strip, usuario: usuario_actual)
    redirect_to caja_ventas_path, notice: t("caja.avisos.devolucion", folio: dev.folio, monto: Dinero.pesos(dev.total_centavos), venta: venta.folio)
  rescue Caja::Error, ActiveRecord::RecordInvalid => e
    redirect_to caja_devolucion_path(codigo: params[:codigo]), alert: e.message
  end

  private

  def corte_para_resumen
    raise SinPermiso, "caja.abrir" unless puede?("caja.abrir") || puede?("reportes.ver")
    Corte.where(sucursal: sucursal_actual).find(params[:id])
  end

  def imprimir_en_red(bytes)
    Impresora.enviar!(sucursal_actual.impresora_red, bytes)
    render json: { ok: true, aviso: t("caja.impreso") }
  rescue Impresora::Error => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  # Lo que la pantalla de caja necesita de un producto para armar su renglón; nil si no tiene precio aquí.
  def datos_pos(p)
    catalogo = p.precio_centavos_en(sucursal_actual)
    return unless catalogo.positive?
    promos = Promocion.para(p, sucursal_actual).select(&:vigente?).map do |pr|
      { tipo: pr.tipo, cantidad_minima: pr.cantidad_minima, precio_centavos: pr.precio_centavos, porcentaje: pr.porcentaje, nombre: pr.nombre }
    end
    { producto_id: p.id, nombre: p.nombre, unidad: p.unidad, decimales: p.decimales, precio_centavos: catalogo, promociones: promos }
  end

  # Un cierre frenado no se pierde: queda en Revisión a nombre de quien contó.
  def reportar_cierre_frenado(contado, diferencia, decision)
    texto = t("caja.cierre_frenado", contado: Dinero.pesos(contado), diferencia: Dinero.pesos(diferencia), motivo: decision.motivo)
    texto += "\n#{t("regla_corte.fallo", error: decision.error)}" if decision.error
    Revision.abrir!(@corte, usuario: usuario_actual, sucursal: sucursal_actual, motivo: texto, valor_centavos: diferencia.abs, frenado: true)
  end

  def cargar_corte
    @corte = Corte.abierto_en(sucursal_actual)
  end
end
