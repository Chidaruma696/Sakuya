# El editor del tablero de Inicio: el programa en Lisp a la izquierda y cómo queda a la derecha.
# Probar no guarda nada; guardar asienta una versión nueva solo si el programa corre; restaurar
# asienta otra vez una versión vieja.
class TableroController < ApplicationController
  include ConTablero

  before_action { autorizar!("reglas.editar") }
  before_action :rango

  def edit
    @codigo = Regla.vigente("tablero")&.codigo.presence || Tablero::DE_FABRICA
    vista_previa(@codigo)
  end

  def probar
    @codigo = params[:codigo].to_s
    vista_previa(@codigo)
    render :edit, status: (@error_programa ? :unprocessable_entity : :ok)
  end

  def guardar
    @codigo = params[:codigo].to_s
    vista_previa(@codigo)
    return render(:edit, status: :unprocessable_entity) if @error_programa
    Regla.create!(gancho: "tablero", codigo: @codigo, usuario: usuario_actual)
    redirect_to root_path, notice: t("tablero.avisos.guardado")
  rescue ActiveRecord::RecordInvalid => e
    @error_programa = e.record.errors.full_messages.to_sentence
    render :edit, status: :unprocessable_entity
  end

  def restaurar
    vieja = Regla.de("tablero").find(params[:id])
    Regla.create!(gancho: "tablero", codigo: vieja.codigo, usuario: usuario_actual)
    redirect_to tablero_editar_path, notice: t("tablero.avisos.restaurado", fecha: l(vieja.created_at, format: :short))
  end

  private

  # A diferencia de Inicio, aquí el error no se esconde detrás del tablero de fábrica: se enseña.
  def vista_previa(codigo)
    armar_tablero(codigo: codigo)
    @error_programa = @tablero_error
    @versiones = Regla.de("tablero").includes(:usuario).limit(15)
  end
end
