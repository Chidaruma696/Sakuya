require "csv"

# La portada es el tablero. Quien no puede ver reportes ve una bienvenida con lo que sí puede hacer.
class InicioController < ApplicationController
  include ConTablero

  before_action :rango, if: -> { puede?("reportes.ver") }
  before_action(only: :ventas) { autorizar!("reportes.ver") }

  def index
    @por_revisar = Revision.pendientes.where(sucursal: sucursal_actual.matriz? ? Sucursal.all : sucursal_actual).count if puede?("revisiones.resolver")
    return render :bienvenida unless puede?("reportes.ver")

    armar_tablero
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
end
