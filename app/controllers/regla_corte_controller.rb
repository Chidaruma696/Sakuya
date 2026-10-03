# El editor de la regla del corte, en Ajustes › Opciones avanzadas. Igual que el del tablero:
# probar no guarda; guardar asienta una versión nueva solo si la regla decide algo con el caso de
# prueba; restaurar asienta otra vez una vieja.
class ReglaCorteController < ApplicationController
  before_action { autorizar!("reglas.editar") }
  before_action :caso

  def edit
    @codigo = Regla.vigente("corte")&.codigo.presence || ReglaCorte::DE_FABRICA
    cargar_versiones
  end

  # «Probar» y «Guardar» van a la misma dirección, como en el tablero; probar lleva probar=1.
  def guardar
    @codigo = params[:codigo].to_s
    @decision = probar(@codigo)
    cargar_versiones
    return render(:edit, status: @error_programa ? :unprocessable_entity : :ok) if params[:probar].present? || @error_programa
    Regla.create!(gancho: "corte", codigo: @codigo, usuario: usuario_actual)
    redirect_to regla_corte_editar_path, notice: t("regla_corte.avisos.guardado")
  rescue ActiveRecord::RecordInvalid => e
    @error_programa = e.record.errors.full_messages.to_sentence
    render :edit, status: :unprocessable_entity
  end

  def restaurar
    vieja = Regla.de("corte").find(params[:id])
    Regla.create!(gancho: "corte", codigo: vieja.codigo, usuario: usuario_actual)
    redirect_to regla_corte_editar_path, notice: t("regla_corte.avisos.restaurado", fecha: l(vieja.created_at, format: :short))
  end

  private

  # El caso de prueba: lo que se espera en la gaveta, lo que se contó y si cierra alguien con
  # permiso. De entrada, lo que espera el corte abierto de la sucursal.
  def caso
    esperado = Corte.abierto_en(sucursal_actual)&.efectivo_esperado_centavos || 50_000
    @esperado = params[:esperado].present? ? Dinero.centavos(params[:esperado]) : esperado
    @contado = params[:contado].present? ? Dinero.centavos(params[:contado]) : @esperado
    @autorizado = params[:autorizado] == "1"
  end

  def probar(codigo)
    ReglaCorte.probar(codigo, esperado_centavos: @esperado, contado_centavos: @contado, autorizado: @autorizado)
  rescue Lisp::Error => e
    @error_programa = e.message
    nil
  end

  def cargar_versiones
    @versiones = Regla.de("corte").includes(:usuario).limit(15)
  end
end
