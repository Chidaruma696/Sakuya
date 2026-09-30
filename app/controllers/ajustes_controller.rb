# Ajustes: una página con barra lateral y secciones. "Para ti" (idioma, tema, densidad, letra) es de
# cada quien; el resto (negocio y ticket, módulos, caja) solo para quien administra usuarios.
class AjustesController < ApplicationController
  pestana :ajustes

  SECCIONES = %w[para_ti negocio folios modulos caja compras].freeze

  def index
    @seccion = params[:seccion].presence_in(SECCIONES) || (params[:seccion] == "ticket" ? "negocio" : "para_ti")
    autorizar!("admin.usuarios") unless @seccion == "para_ti"
    @ajustes = Ajuste.todos
    if @seccion == "negocio"
      @venta = venta_de_muestra
      @previa = true
    end
  end

  def preferencias
    usuario_actual.update!(params.require(:usuario).permit(:idioma, :tema, :densidad, :letra))
    redirect_to ajustes_path, notice: I18n.t("ajustes.guardado", locale: usuario_actual.idioma)
  rescue ActiveRecord::RecordInvalid => e
    redirect_to ajustes_path, alert: e.record.errors.full_messages.join(", ")
  end

  def guardar_ticket
    autorizar!("admin.usuarios")
    Ajuste.guardar!(params.fetch(:ajuste, {}).to_unsafe_h)
    redirect_to ajustes_seccion_path("negocio"), notice: t("ajustes.guardado")
  rescue ArgumentError, ActiveRecord::RecordInvalid => e
    redirect_to ajustes_seccion_path("negocio"), alert: e.message
  end

  def sistema
    autorizar!("admin.usuarios")
    Ajuste.guardar!(params.fetch(:ajuste, {}).to_unsafe_h)
    Modulo.guardar!(params[:modulos]) if params.key?(:modulos)
    redirect_to volver, notice: t("ajustes.guardado")
  rescue ArgumentError, ActiveRecord::RecordInvalid => e
    redirect_to volver, alert: e.message
  end

  private

  # A qué sección regresa el formulario del sistema.
  def volver
    ajustes_seccion_path(params[:volver].presence_in(SECCIONES) || "modulos")
  end

  # Una venta inventada, en memoria, para la vista previa del ticket.
  def venta_de_muestra
    v = Venta.new(sucursal: sucursal_actual, usuario: usuario_actual, folio: "B-00042", codigo: Barcode.ean13("090000000042"),
                  created_at: Time.current, total_centavos: 21_450, cambio_centavos: 3_550, estado: "cobrada")
    [ [ t("ajustes.ticket.muestra.producto_kg"), "kg", "1.250", 12_900 ], [ t("ajustes.ticket.muestra.producto_pieza"), "pieza", "2", 2_650 ] ].each do |nombre, unidad, cant, precio|
      cantidad = BigDecimal(cant)
      v.lineas.build(producto: Producto.new(nombre: nombre, unidad: unidad), cantidad: cantidad, precio_centavos: precio,
                     catalogo_centavos: precio, importe_centavos: (cantidad * precio).round.to_i)
    end
    v.pagos.build(forma: "efectivo", monto_centavos: 25_000)
    v
  end
end
