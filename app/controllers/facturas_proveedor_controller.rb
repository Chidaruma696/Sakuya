# Facturas del proveedor: crean la deuda. Con renglones (el precio vive solo aquí) o solo monto.
class FacturasProveedorController < ApplicationController
  pestana :compras
  modulo :compras

  before_action { autorizar!("compras.ver") }

  def index
    @facturas = FacturaProveedor.includes(:proveedor, :usuario, :pagos, :lineas, :recepciones).order(fecha: :desc, id: :desc).limit(200)
    @facturas = @facturas.where(proveedor_id: params[:proveedor_id]) if params[:proveedor_id].present?
    @proveedores = Proveedor.order(:nombre)
  end

  def new
    autorizar!("compras.facturar")
    @factura = FacturaProveedor.new(fecha: Date.current, proveedor_id: params[:proveedor_id])
    @factura.lineas.build
    @proveedores = Proveedor.activos.order(:nombre)
    @productos = Producto.activos.order(:nombre)
    @sueltas = Recepcion.registradas.where(factura_proveedor_id: nil).includes(:proveedor, :sucursal).order(fecha: :desc).limit(60)
    @candado = Ajuste["compras.candado_recibido"] == "1"
  end

  # Con el candado de Ajustes › Compras, facturar más de lo que traen las recepciones ligadas exige
  # motivo (o compras.exceder) y la factura queda por revisar con el exceso valuado.
  def create
    autorizar!("compras.facturar")
    d = params.require(:factura)
    proveedor = Proveedor.activos.find(d[:proveedor_id])
    lineas = (d[:lineas_attributes]&.to_unsafe_h || {}).values.map(&:symbolize_keys).reject { |l| l[:producto_id].blank? || BigDecimal(l[:cantidad].to_s.presence || "0") <= 0 }
    recepciones = Recepcion.where(id: Array(d[:recepcion_ids]), proveedor: proveedor, factura_proveedor_id: nil, estado: "registrada").to_a
    exceso = Ajuste["compras.candado_recibido"] == "1" ? Compras.excedente(lineas, recepciones) : []
    autoriza = exceso.any? ? autorizador_o_revision("compras.exceder") : usuario_actual
    detalle = exceso.map { |c| "#{c.producto.nombre} +#{helpers.cantidad(-c.diferencia, c.producto)}" }.join(", ")
    raise ArgumentError, t("errores.compras.excede_recibido", detalle: detalle) if autoriza.nil? && d[:motivo].blank?
    factura = Compras.facturar!(proveedor: proveedor, sucursal: sucursal_actual, usuario: usuario_actual, folio: d[:folio].to_s, fecha: Date.parse(d[:fecha].presence || Date.current.to_s),
                                vence: (Date.parse(d[:vence]) if d[:vence].present?), concepto: d[:concepto], monto_centavos: Dinero.centavos(d[:monto]), lineas: lineas)
    recepciones.each { |r| Compras.ligar!(r, factura) }
    valor = exceso.sum { |c| Dinero.importe(-c.diferencia, factura.lineas.where(producto: c.producto).maximum(:precio_centavos).to_i) }
    revisar_si_hace_falta(factura, autoriza, motivo: "#{d[:motivo]} (#{detalle})", valor_centavos: valor)
    redirect_to factura_path(factura), notice: t("compras.avisos.facturada", folio: factura.folio, monto: Dinero.pesos(factura.monto_centavos)) + (autoriza ? "" : t("caja.avisos.queda_por_revisar"))
  rescue ArgumentError, ActiveRecord::RecordInvalid, ActiveRecord::RecordNotFound => e
    redirect_to new_factura_path(proveedor_id: d && d[:proveedor_id]), alert: e.message
  end

  def show
    @factura = FacturaProveedor.includes(:proveedor, :usuario, lineas: :producto, recepciones: %i[usuario sucursal], pagos: %i[usuario retiro]).find(params[:id])
    @comparativo = Compras.comparativo(@factura)
    @sueltas = @factura.proveedor.recepciones.registradas.where(factura_proveedor_id: nil).order(fecha: :desc).limit(30)
  end

  def cancelar
    autorizar!("compras.facturar")
    factura = FacturaProveedor.find(params[:id])
    Compras.cancelar_factura!(factura, motivo: params[:motivo].to_s.strip, usuario: usuario_actual)
    redirect_to factura_path(factura), notice: t("compras.avisos.factura_cancelada", folio: factura.folio)
  rescue ArgumentError, ActiveRecord::RecordInvalid => e
    redirect_to factura_path(factura), alert: e.message
  end
end
