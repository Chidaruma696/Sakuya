require "csv"

# La portada es el tablero. Quien no puede ver reportes ve una bienvenida con lo que sí puede hacer.
class InicioController < ApplicationController
  before_action :rango, if: -> { puede?("reportes.ver") }
  before_action(only: :ventas) { autorizar!("reportes.ver") }

  def index
    @por_revisar = Revision.pendientes.where(sucursal: sucursal_actual.matriz? ? Sucursal.all : sucursal_actual).count if puede?("revisiones.resolver")
    return render :bienvenida unless puede?("reportes.ver")

    ventas = ventas_del_rango
    @tickets = ventas.count
    @total = ventas.sum(:total_centavos)
    @promedio = @tickets.zero? ? 0 : @total / @tickets
    @por_forma = Pago.where(venta: ventas).group(:forma).sum(:monto_centavos)
    @cambio = ventas.sum(:cambio_centavos)
    @devoluciones = Devolucion.where(venta: ventas).sum(:total_centavos)
    @top = VentaLinea.where(venta: ventas).joins(:producto).group("productos.nombre", "productos.unidad")
                     .order(Arel.sql("SUM(importe_centavos) DESC")).limit(10).pluck("productos.nombre", "productos.unidad", Arel.sql("SUM(cantidad)"), Arel.sql("SUM(importe_centavos)"))
    @cortes = Corte.where(sucursal: sucursales, estado: "cerrado", cerrado_en: @desde.beginning_of_day..@hasta.end_of_day).includes(:sucursal, :usuario).order(cerrado_en: :desc)
    @conteos = Conteo.where(sucursal: sucursales, estado: "cerrado", cerrado_en: @desde.beginning_of_day..@hasta.end_of_day).includes(:sucursal, :responsable)
    @toca_contar = sucursales.select { |s| Conteo.vencido?(s) }
    @valor_existencias = Existencia.where(sucursal: sucursales).joins(:producto).sum("existencias.cantidad * productos.precio_centavos").to_i
  end

  def ventas
    @filas = VentaLinea.where(venta: ventas_del_rango).joins(:producto).group("productos.clave", "productos.nombre", "productos.unidad")
                       .order("productos.nombre").pluck("productos.clave", "productos.nombre", "productos.unidad", Arel.sql("SUM(cantidad)"), Arel.sql("SUM(importe_centavos)"), Arel.sql("COUNT(*)"))
    respond_to do |format|
      format.html
      format.csv do
        csv = CSV.generate(col_sep: ";") do |c|
          c << %w[clave producto unidad cantidad importe lineas].map { |k| t("inicio.csv.#{k}") }
          @filas.each { |f| c << [ f[0], f[1], f[2], BigDecimal(f[3].to_s).round(3).to_s("F"), (f[4].to_i / 100.0).round(2), f[5] ] }
        end
        send_data csv, filename: "ventas-#{@desde}-#{@hasta}.csv", type: "text/csv"
      end
    end
  end

  private

  def rango
    @desde = (Date.parse(params[:desde]) rescue Date.current)
    @hasta = (Date.parse(params[:hasta]) rescue Date.current)
    @desde, @hasta = @hasta, @desde if @desde > @hasta
    @todas = sucursal_actual.matriz? && params[:sucursal_id] == "todas"
    @sucursal = if sucursal_actual.matriz? && params[:sucursal_id].present? && !@todas
      Sucursal.find(params[:sucursal_id])
    else
      sucursal_actual
    end
  end

  def sucursales
    @todas ? Sucursal.all : [ @sucursal ]
  end

  def ventas_del_rango
    Venta.where(sucursal: sucursales, fecha_negocio: @desde..@hasta)
  end
end
