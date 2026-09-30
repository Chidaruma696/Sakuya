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

  def create
    autorizar!("compras.recibir")
    d = params.require(:recepcion)
    proveedor = Proveedor.activos.find(d[:proveedor_id])
    factura = proveedor.facturas.abiertas.find_by(id: d[:factura_proveedor_id].presence)
    recepcion = Compras.recibir!(sucursal: sucursal_actual, proveedor: proveedor, usuario: usuario_actual, remision: d[:remision], factura: factura,
                                 notas: d[:notas], fecha: d[:fecha].presence || Date.current,
                                 clave: d[:clave], lineas: (d[:lineas_attributes]&.to_unsafe_h || {}).values)
    redirect_to recepcion_path(recepcion), notice: t("compras.avisos.recibida", folio: recepcion.folio)
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
end
