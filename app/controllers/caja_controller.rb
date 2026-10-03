class CajaController < ApplicationController
  pestana :caja

  before_action :cargar_corte

  # ---- vender
  def index
    autorizar!("caja.vender")
    @clave = SecureRandom.uuid
  end

  # Qué es lo que se escaneó o tecleó, para el ticket (JSON).
  def escanear
    autorizar!("caja.vender")
    r = Escaneo.resolver(params[:codigo])
    return render json: { error: "No se encontró «#{params[:codigo]}»" }, status: :not_found unless r
    p = r.producto
    catalogo = p.precio_centavos_en(sucursal_actual)
    return render json: { error: t("errores.caja.sin_precio", producto: p.nombre, sucursal: sucursal_actual.nombre) }, status: :unprocessable_entity unless catalogo.positive?
    promos = Promocion.para(p, sucursal_actual).select(&:vigente?).map do |pr|
      { tipo: pr.tipo, cantidad_minima: pr.cantidad_minima, precio_centavos: pr.precio_centavos, porcentaje: pr.porcentaje, nombre: pr.nombre }
    end
    render json: { producto_id: p.id, nombre: p.nombre, unidad: p.unidad, decimales: p.decimales,
                   precio_centavos: catalogo, promociones: promos }
  end

  def cobrar
    autorizar!("caja.vender")
    lineas = JSON.parse(params[:lineas].to_s).map { |l| l.symbolize_keys.slice(:producto_id, :cantidad, :precio_centavos) }
    pagos = JSON.parse(params[:pagos].to_s).map(&:symbolize_keys)
    autoriza = autorizador_o_revision("caja.bajar_precio")
    venta = Caja.cobrar!(sucursal: sucursal_actual, usuario: usuario_actual, lineas: lineas, pagos: pagos, clave: params[:clave], autorizador: autoriza)
    # Bajó precios sin tener el permiso: cada renglón queda por revisar con lo que dejó de cobrar.
    venta.lineas.where(autorizado_por: nil).where("precio_centavos < catalogo_centavos").includes(:producto).each do |l|
      revisar_si_hace_falta(l, nil, motivo: t("caja.avisos.bajo_precio", producto: l.producto.nombre, de: Dinero.pesos(l.catalogo_centavos), a: Dinero.pesos(l.precio_centavos), folio: venta.folio),
                            valor_centavos: Dinero.importe(l.cantidad, l.catalogo_centavos - l.precio_centavos))
    end
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
    render layout: "ticket"
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
  # rechaza no se cierra, salvo que cierre alguien con caja.diferencia (entonces queda por revisar).
  def cerrar
    autorizar!("caja.abrir")
    raise ArgumentError, t("errores.caja.sin_caja_simple") unless @corte
    desglose = params.fetch(:denominacion, {}).to_unsafe_h.select { |_, c| c.to_i.positive? }
    contado = desglose.any? ? Corte.sumar(desglose) : Dinero.centavos(params[:contado])
    diferencia = contado - @corte.efectivo_esperado_centavos
    decision = ReglaCorte.decidir(@corte, contado_centavos: contado, usuario: usuario_actual)
    raise ArgumentError, t("errores.corte.rechazado", motivo: decision.motivo) if decision.rechaza? && !puede?("caja.diferencia")
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

  def retirar
    raise ArgumentError, t("errores.caja.sin_caja_simple") unless @corte
    autoriza = autorizador_o_revision("caja.retirar")
    retiro = @corte.retirar!(monto_centavos: Dinero.centavos(params[:monto]), motivo: params[:motivo], usuario: usuario_actual, autorizado_por: autoriza)
    revisar_si_hace_falta(retiro, autoriza, motivo: retiro.motivo, valor_centavos: retiro.monto_centavos)
    redirect_to caja_corte_path, notice: t("caja.avisos.retiro", monto: Dinero.pesos(retiro.monto_centavos)) + (autoriza ? "" : t("caja.avisos.queda_por_revisar"))
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

  def cargar_corte
    @corte = Corte.abierto_en(sucursal_actual)
  end
end
