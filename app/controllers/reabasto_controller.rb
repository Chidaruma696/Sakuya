# Reabastecer sucursales: lo que a cada una le falta según sus mínimos y máximos, y de ahí un
# traspaso ya armado (que se revisa y se registra como cualquier otro).
class ReabastoController < ApplicationController
  pestana :almacenes
  modulo :almacenes

  before_action { autorizar!("almacenes.traspasar") }

  def index
    @sucursales = Sucursal.activas.con_caja.order(:nombre).to_a
    @sugeridos = @sucursales.to_h { |s| [ s.id, Minimo.sugerido(s) ] }
  end

  def minimos
    @sucursal = Sucursal.activas.find(params[:sucursal_id])
    @productos = Producto.activos.order(:nombre)
    @minimos = Minimo.where(sucursal: @sucursal).index_by(&:producto_id)
    @existencias = Existencia.where(sucursal: @sucursal).pluck(:producto_id, :cantidad).to_h
  end

  def guardar_minimos
    sucursal = Sucursal.activas.find(params[:sucursal_id])
    Minimo.guardar!(sucursal, params.fetch(:minimos, {}).to_unsafe_h.transform_values(&:symbolize_keys))
    redirect_to reabasto_path, notice: t("reabasto.avisos.guardados", sucursal: sucursal.nombre)
  rescue ActiveRecord::RecordInvalid => e
    redirect_to reabasto_minimos_path(sucursal_id: sucursal.id), alert: e.message
  end
end
