# Pantalla de primer arranque: solo existe mientras no haya ningún usuario activo.
class InstalacionController < ApplicationController
  skip_before_action :exigir_instalacion, :exigir_sesion
  layout "sesion"

  CAMPOS = %i[negocio giro sucursal codigo nombre usuario password idioma tema densidad letra folios_modo folios_letra folios_venta].freeze

  def new
    return redirect_to root_path if Usuario.activos.exists?
    @datos = { giro: "todo", codigo: "MTZ", usuario: "admin", idioma: I18n.locale.to_s, tema: "claro", densidad: "normal", letra: "normal", folios_modo: "por_documento", folios_letra: "propia", folios_venta: "B" }
    @paso = 1
  end

  def create
    return redirect_to root_path if Usuario.activos.exists?
    @datos = params.require(:instalacion).permit(*CAMPOS).to_h.symbolize_keys
    admin = Instalacion.instalar!(**CAMPOS.index_with { |c| @datos[c] })
    iniciar_sesion(admin)
    redirect_to root_path, notice: I18n.t("instalacion.lista", locale: admin.idioma)
  rescue ActiveRecord::RecordInvalid, ArgumentError => e
    flash.now[:alert] = e.respond_to?(:record) ? e.record.errors.full_messages.join(", ") : e.message
    @paso = 6
    render :new, status: :unprocessable_entity
  end
end
