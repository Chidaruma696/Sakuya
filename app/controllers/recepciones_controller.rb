# Recepción de mercancía del proveedor: se escanea o se elige el producto, se anota cuánto llegó y
# entra al inventario. La factura se liga cuando llega.
class RecepcionesController < ApplicationController
  pestana :compras
  modulo :compras

  before_action { autorizar!("compras.ver") }

  def index
    @recepciones = Recepcion.where(sucursal: sucursal_actual).includes(:proveedor, :usuario, :factura, lineas: :producto).order(created_at: :desc).limit(100)
  end

  def new
    autorizar!("compras.recibir")
    @recepcion = Recepcion.new(fecha: Date.current)
    @recepcion.lineas.build
    @proveedores = Proveedor.activos.order(:nombre)
    @productos = Producto.activos.order(:nombre)
    @clave = SecureRandom.hex(8)
  end

  # Lo que llega lo juzga la regla de recepciones (ReglaRecepcion): lo que frena no entra y queda
  # reportado en el proveedor; con compras.forzar_recepcion entra y queda por revisar.
  def create
    autorizar!("compras.recibir")
    d = params.require(:recepcion)
    proveedor = Proveedor.activos.find(d[:proveedor_id])
    factura = proveedor.facturas.abiertas.find_by(id: d[:factura_proveedor_id].presence)
    lineas = (d[:lineas_attributes]&.to_unsafe_h || {}).values
    if d[:clave].blank? || !Recepcion.exists?(sucursal: sucursal_actual, clave: d[:clave])
      revisar = juzgar(proveedor, lineas, d[:remision], factura.present?)
    end
    recepcion = Compras.recibir!(sucursal: sucursal_actual, proveedor: proveedor, usuario: usuario_actual, remision: d[:remision], factura: factura,
                                 notas: d[:notas], fecha: d[:fecha].presence || Date.current, clave: d[:clave], lineas: lineas)
    Revision.abrir!(recepcion, usuario: usuario_actual, sucursal: sucursal_actual, motivo: revisar, valor_centavos: @valor) if revisar
    redirect_to recepcion_path(recepcion), notice: t("compras.avisos.recibida", folio: recepcion.folio) + (revisar ? t("caja.avisos.queda_por_revisar") : "")
  rescue ArgumentError, ActiveRecord::RecordInvalid, ActiveRecord::RecordNotFound => e
    redirect_to new_recepcion_path, alert: e.message
  end

  def show
    @recepcion = Recepcion.includes(:proveedor, :usuario, :factura, lineas: :producto).find(params[:id])
    @facturas = @recepcion.proveedor.facturas.abiertas.order(fecha: :desc).limit(50)
  end

  def cancelar
    autorizar!("compras.recibir")
    recepcion = Recepcion.find(params[:id])
    Compras.cancelar_recepcion!(recepcion, motivo: params[:motivo].to_s.strip, usuario: usuario_actual)
    redirect_to recepcion_path(recepcion), notice: t("compras.avisos.recepcion_cancelada", folio: recepcion.folio)
  rescue ArgumentError, ActiveRecord::RecordInvalid => e
    redirect_to recepcion_path(recepcion), alert: e.message
  end

  # Ligar (o soltar) la factura del proveedor.
  def factura
    autorizar!("compras.facturar")
    recepcion = Recepcion.find(params[:id])
    factura = recepcion.proveedor.facturas.find_by(id: params[:factura_proveedor_id].presence)
    Compras.ligar!(recepcion, factura)
    redirect_to recepcion_path(recepcion), notice: factura ? t("compras.avisos.ligada", folio: factura.folio) : t("compras.avisos.desligada")
  rescue ArgumentError, ActiveRecord::RecordInvalid => e
    redirect_to recepcion_path(recepcion), alert: e.message
  end

  private

  # Devuelve el motivo para revisarla (o nil); si la regla frena y no hay permiso, reporta y avisa.
  def juzgar(proveedor, lineas, remision, facturada)
    con_permiso = puede?("compras.forzar_recepcion")
    datos = ReglaRecepcion.datos(sucursal: sucursal_actual, proveedor: proveedor, lineas: lineas, remision: remision, facturada: facturada, autorizado: con_permiso)
    @valor = datos.valor
    decision = ReglaRecepcion.decidir(datos)
    fallo = (t("regla_recepcion.fallo", error: decision.error) if decision.error)
    if decision.rechaza? && !con_permiso
      reporte = [ t("compras.recepcion_frenada", motivo: decision.motivo), fallo ].compact.join("\n")
      Revision.abrir!(proveedor, usuario: usuario_actual, sucursal: sucursal_actual, motivo: reporte, valor_centavos: @valor, frenado: true)
      raise ArgumentError, t("errores.compras.recepcion_frenada", motivo: decision.motivo)
    end
    [ (decision.motivo unless decision.permite?), fallo ].compact.join("\n").presence
  end
end
