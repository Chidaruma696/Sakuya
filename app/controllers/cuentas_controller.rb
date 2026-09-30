# Cuentas por pagar: cuánto se debe a cada proveedor, qué facturas vencen, y el pago desde la caja.
class CuentasController < ApplicationController
  pestana :compras
  modulo :compras

  before_action { autorizar!("compras.ver") }

  def index
    saldos = MovimientoProveedor.group(:proveedor_id).sum(:delta_centavos)
    @proveedores = Proveedor.where(id: saldos.keys).order(:nombre).map { |p| [ p, saldos[p.id] ] }.reject { |_, s| s.zero? }
    @total = @proveedores.sum { |_, s| s }
    @vencidas = FacturaProveedor.abiertas.includes(:proveedor, :pagos).where("vence < ?", Date.current).order(:vence).reject(&:pagada?)
    @por_vencer = FacturaProveedor.abiertas.includes(:proveedor, :pagos).where(vence: Date.current..(Date.current + 7)).order(:vence).reject(&:pagada?)
  end

  def show
    @proveedor = Proveedor.find(params[:id])
    @facturas = @proveedor.facturas.abiertas.includes(:pagos).order(fecha: :desc).limit(100).reject(&:pagada?)
    @movimientos = @proveedor.movimientos.includes(:usuario, :factura, :pago).order(id: :desc).limit(200)
    @pagos = @proveedor.pagos.includes(:usuario, :factura, :corte).order(id: :desc).limit(50)
    @corte = Corte.abierto_en(sucursal_actual)
  end

  def pagar
    autorizar!("compras.pagar")
    proveedor = Proveedor.find(params[:id])
    factura = proveedor.facturas.find_by(id: params[:factura_proveedor_id].presence)
    pago = Compras.pagar!(proveedor: proveedor, sucursal: sucursal_actual, usuario: usuario_actual, monto_centavos: Dinero.centavos(params[:monto]),
                          forma: params[:forma].to_s, factura: factura, referencia: params[:referencia])
    redirect_to cuenta_path(proveedor), notice: t("compras.avisos.pagado", monto: Dinero.pesos(pago.monto_centavos), proveedor: proveedor.nombre, saldo: Dinero.pesos(proveedor.saldo_centavos))
  rescue ArgumentError, ActiveRecord::RecordInvalid => e
    redirect_to cuenta_path(proveedor), alert: e.message
  end

  def anular_pago
    autorizar!("compras.pagar")
    pago = PagoProveedor.find(params[:id])
    Compras.anular_pago!(pago, motivo: params[:motivo].to_s.strip, usuario: usuario_actual)
    redirect_to cuenta_path(pago.proveedor), notice: t("compras.avisos.pago_anulado", monto: Dinero.pesos(pago.monto_centavos))
  rescue ArgumentError, ActiveRecord::RecordInvalid => e
    redirect_to cuenta_path(pago.proveedor), alert: e.message
  end
end
