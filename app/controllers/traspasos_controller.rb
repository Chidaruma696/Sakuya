# Traspasos: mercancía de una sucursal a otra. Es la puerta de los
# almacenes.
class TraspasosController < ApplicationController
  pestana :almacenes
  modulo :almacenes

  before_action { autorizar!("almacenes.traspasar") }

  def index
    @traspasos = Traspaso.where("sucursal_origen_id = :s OR sucursal_destino_id = :s", s: sucursal_actual.id)
                         .includes(:sucursal_origen, :sucursal_destino, :usuario, lineas: :producto).order(created_at: :desc).limit(100)
  end

  def new
    @traspaso = Traspaso.new(fecha: Date.current, sucursal_origen: sucursal_actual)
    @traspaso.lineas.build
    @origenes = sucursal_actual.matriz? ? Sucursal.activas.order(:nombre) : [ sucursal_actual ]
    @destinos = Sucursal.activas.order(:nombre)
    @productos = Producto.activos.order(:nombre)
    @clave = SecureRandom.hex(8)
  end

  def create
    d = params.require(:traspaso)
    origen = sucursal_actual.matriz? ? Sucursal.activas.find(d[:sucursal_origen_id]) : sucursal_actual
    destino = Sucursal.activas.find(d[:sucursal_destino_id])
    traspaso = Traspaso.registrar!(origen: origen, destino: destino, usuario: usuario_actual, notas: d[:notas], clave: d[:clave],
                                   fecha: d[:fecha].presence || Date.current, lineas: (d[:lineas_attributes]&.to_unsafe_h || {}).values)
    redirect_to traspaso_path(traspaso), notice: t("traspasos.avisos.registrado", folio: traspaso.folio, destino: destino.nombre)
  rescue ArgumentError, ActiveRecord::RecordInvalid, ActiveRecord::RecordNotFound, Inventario::SinExistencia => e
    redirect_to new_traspaso_path, alert: e.message
  end

  def show
    @traspaso = Traspaso.includes(:sucursal_origen, :sucursal_destino, :usuario, lineas: :producto).find(params[:id])
  end

  def cancelar
    traspaso = Traspaso.find(params[:id])
    traspaso.cancelar!(motivo: params[:motivo].to_s.strip, usuario: usuario_actual)
    redirect_to traspaso_path(traspaso), notice: t("traspasos.avisos.cancelado", folio: traspaso.folio)
  rescue ArgumentError, ActiveRecord::RecordInvalid, Inventario::SinExistencia => e
    redirect_to traspaso_path(traspaso), alert: e.message
  end
end
