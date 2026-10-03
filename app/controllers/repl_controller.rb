# El REPL de solo lectura, en Ajustes › Opciones avanzadas. Lo que se escribe se evalúa contra los
# datos en vivo (la matriz ve todas las sucursales; una tienda, la suya) y nada se guarda, salvo
# las últimas preguntas en la sesión para volver a ellas.
class ReplController < ApplicationController
  HISTORIAL = 10 # va en la cookie de sesión: pocas y cortas

  before_action { autorizar!("reglas.editar") }

  def show
    @texto = params[:texto].presence || "(sales)"
    @historial = session[:repl] || []
    @informes = informes
  end

  # Quién le ha preguntado qué al REPL, lo último primero.
  def bitacora
    @consultas = ConsultaRepl.includes(:usuario, :sucursal).order(id: :desc).limit(200)
  end

  def evaluar
    @texto = params[:texto].to_s
    begin
      @valor = Repl.evaluar(@texto, sucursales: sucursal_actual.matriz? ? Sucursal.all : [ sucursal_actual ])
      @evaluado = true
    rescue Lisp::Error => e
      @error = e.message
    end
    session[:repl] = ([ @texto.strip ] + (session[:repl] || [])).uniq.first(HISTORIAL) if @texto.present? && @texto.size <= 300
    # Fuera del bloqueo de escrituras: la bitácora sí se escribe.
    ConsultaRepl.create!(usuario: usuario_actual, sucursal: sucursal_actual, texto: @texto.strip, ok: @error.nil?) if @texto.present?
    @historial = session[:repl]
    @informes = informes
    render :show, status: @error ? :unprocessable_entity : :ok
  end

  private

  # Los informes que traen los plugins encendidos; si alguno ya no se lee, no estorba al REPL.
  def informes
    Plugin.informes
  rescue Lisp::Error
    []
  end
end
