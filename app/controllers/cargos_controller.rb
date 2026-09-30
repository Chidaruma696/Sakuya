class CargosController < ApplicationController
  pestana :conteos
  modulo :conteos

  before_action { autorizar!("conteos.cargos") }

  def index
    @cargos = Cargo.where(sucursal: sucursal_actual).includes(:usuario, :conteo, :revision, :resuelto_por).order(created_at: :desc).limit(100)
  end

  def resolver
    cargo = Cargo.where(sucursal: sucursal_actual).find(params[:id])
    cargo.resolver!(params[:estado].presence_in(%w[cobrado perdonado]) || "cobrado", usuario: usuario_actual)
    redirect_to cargos_path, notice: t("cargos.avisos.marcado", quien: cargo.usuario, estado: t("estados.#{cargo.estado}"))
  rescue ArgumentError => e
    redirect_to cargos_path, alert: e.message
  end
end
