# La bandeja de autorización diferida: lo que se hizo sin nadie que lo autorizara al momento.
# El supervisor lo ve todo junto al final del día y decide: aprobar, u observar (y cargar).
class RevisionesController < ApplicationController
  pestana :inicio

  before_action { autorizar!("revisiones.resolver") }

  def index
    @todas = sucursal_actual.matriz? && params[:sucursal_id] == "todas"
    ambito = @todas ? Revision.all : Revision.where(sucursal: sucursal_actual)
    @pendientes = ambito.pendientes.includes(:usuario, :sucursal, :revisable).order(:created_at)
    @resueltas = ambito.resueltas.includes(:usuario, :sucursal, :revisado_por, :cargo).order(revisado_en: :desc).limit(30)
  end

  def resolver
    revision = Revision.find(params[:id])
    raise SinPermiso, "revisiones.resolver" unless revision.sucursal_id == sucursal_actual.id || sucursal_actual.matriz?
    if params[:estado] == "observada"
      revision.observar!(usuario: usuario_actual, nota: params[:nota].presence, cargo_centavos: Dinero.centavos(params[:cargo]))
      aviso = revision.cargo ? t("revisiones.observada_cargada", quien: revision.usuario, monto: Dinero.pesos(revision.cargo.monto_centavos)) : t("revisiones.observada_sin_cargo")
    else
      revision.aprobar!(usuario: usuario_actual, nota: params[:nota].presence)
      aviso = t("revisiones.aprobada")
    end
    redirect_to revisiones_path(sucursal_id: params[:sucursal_id]), notice: aviso
  rescue ArgumentError, ActiveRecord::RecordInvalid => e
    redirect_to revisiones_path(sucursal_id: params[:sucursal_id]), alert: e.message
  end
end
