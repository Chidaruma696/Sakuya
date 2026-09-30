# Lo que necesita pintar el tablero de Inicio, compartido con su editor (que lo usa de vista previa):
# el rango de fechas, las sucursales y los datos de cada panel.
module ConTablero
  extend ActiveSupport::Concern

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

  # Arma el tablero con un programa (el vigente si no se da otro) y carga lo de los paneles.
  def armar_tablero(codigo: Regla.vigente("tablero")&.codigo)
    datos = Tablero::Datos.new(sucursales: sucursales, desde: @desde, hasta: @hasta, puede_revisar: puede?("revisiones.resolver"))
    @piezas, @tablero_error = Tablero.armar(datos, codigo: codigo)
    dia = @desde.beginning_of_day..@hasta.end_of_day
    @top = VentaLinea.where(venta: datos.ventas_del_rango).joins(:producto).group("productos.nombre", "productos.unidad")
                     .order(Arel.sql("SUM(importe_centavos) DESC")).limit(50).pluck("productos.nombre", "productos.unidad", Arel.sql("SUM(cantidad)"), Arel.sql("SUM(importe_centavos)"))
    @cortes = Corte.where(sucursal: sucursales, estado: "cerrado", cerrado_en: dia).includes(:sucursal, :usuario).order(cerrado_en: :desc)
    @conteos = Conteo.where(sucursal: sucursales, estado: "cerrado", cerrado_en: dia).includes(:sucursal, :responsable)
    @toca_contar = sucursales.select { |s| Conteo.vencido?(s) }
  end
end
