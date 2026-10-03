# El editor de las reglas que deciden (el cierre de caja, el precio…), en Ajustes › Opciones
# avanzadas. Igual que el del tablero: probar no guarda; guardar asienta una versión nueva solo
# si la regla decide algo con el caso de prueba; restaurar asienta otra vez una vieja. Cada
# gancho pone su caso de prueba (ver `caso` y `probar` en su módulo).
class ReglasController < ApplicationController
  GANCHOS = { "corte" => ReglaCorte, "precio" => ReglaPrecio, "retiro" => ReglaRetiro, "movimiento" => ReglaMovimiento, "factura" => ReglaFactura }.freeze

  before_action { autorizar!("reglas.editar") }
  before_action :cargar

  def edit
    @codigo = Regla.vigente(@gancho)&.codigo.presence || @modulo::DE_FABRICA
  end

  # «Probar» y «Guardar» van a la misma dirección, como en el tablero; probar lleva probar=1.
  def guardar
    @codigo = params[:codigo].to_s
    resultado = probar(@codigo)
    @decisiones = efectivas(resultado.is_a?(Array) ? resultado : [ [ nil, resultado, @caso[:autorizado] ] ]) if resultado
    return render(:edit, status: @error_programa ? :unprocessable_entity : :ok) if params[:probar].present? || @error_programa
    Regla.create!(gancho: @gancho, codigo: @codigo, usuario: usuario_actual)
    redirect_to regla_editar_path(@gancho), notice: t("reglas.avisos.guardado")
  rescue ActiveRecord::RecordInvalid => e
    @error_programa = e.record.errors.full_messages.to_sentence
    render :edit, status: :unprocessable_entity
  end

  def restaurar
    vieja = Regla.de(@gancho).find(params[:id])
    Regla.create!(gancho: @gancho, codigo: vieja.codigo, version: vieja.version, usuario: usuario_actual)
    redirect_to regla_editar_path(@gancho), notice: t("reglas.avisos.restaurado", fecha: l(vieja.created_at, format: :short))
  end

  private

  def cargar
    @gancho = params[:gancho]
    @modulo = GANCHOS.fetch(@gancho)
    @caso = @modulo.caso(params, sucursal_actual)
    @versiones = Regla.de(@gancho).includes(:usuario).limit(15)
  end

  # Lo que de verdad pasaría: el núcleo no deja a nadie con permiso sin poder hacerlo, así que para
  # esa persona frenar es revisar. Devuelve [etiqueta, decisión, si cambió por el permiso].
  def efectivas(lista)
    lista.map do |etiqueta, decision, autorizado|
      por_permiso = decision.rechaza? && autorizado
      [ etiqueta, por_permiso ? decision.with(veredicto: :review) : decision, por_permiso ]
    end
  end

  def probar(codigo)
    @modulo.probar(codigo, @caso)
  rescue Lisp::Error => e
    @error_programa = e.message
    nil
  end
end
