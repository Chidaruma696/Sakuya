class ApplicationController < ActionController::Base
  allow_browser versions: :modern
  stale_when_importmap_changes

  class SinPermiso < StandardError; end

  # Pestaña de la cinta que corresponde a este controlador (ver RibbonHelper).
  class_attribute :pestana_ribbon, default: :inicio
  def self.pestana(id) = self.pestana_ribbon = id

  # Módulos opcionales de los que depende este controlador (ver Modulo); vacío = siempre disponible.
  class_attribute :modulos_requeridos, default: []
  def self.modulo(*claves) = self.modulos_requeridos = claves.map(&:to_s)

  before_action :exigir_instalacion, :exigir_sesion, :exigir_modulo
  around_action :con_idioma
  helper_method :usuario_actual, :sucursal_actual, :puede?

  rescue_from SinPermiso do |e|
    render "errores/sin_permiso", status: :forbidden, locals: { clave: e.message }
  end

  private

  # Cada quien ve el sistema en su idioma; sin sesión, el que pida (?idioma=, se recuerda en una
  # cookie) o el del navegador si lo tenemos.
  def con_idioma(&)
    idiomas = I18n.available_locales.map(&:to_s)
    cookies[:idioma] = params[:idioma] if params[:idioma].presence_in(idiomas)
    idioma = usuario_actual&.idioma || cookies[:idioma].presence_in(idiomas) || http_accept_language_preferido
    I18n.with_locale(idioma, &)
  end

  def http_accept_language_preferido
    request.env["HTTP_ACCEPT_LANGUAGE"].to_s.scan(/[a-z]{2}/).find { |l| I18n.available_locales.map(&:to_s).include?(l) } || I18n.default_locale
  end

  def usuario_actual
    Current.usuario ||= Usuario.activos.includes(:rol, :sucursal).find_by(id: cookies.signed[:usuario_id])
  end

  def sucursal_actual
    Current.sucursal ||= usuario_actual&.sucursal
  end

  # Sin ningún usuario activo el sistema está recién instalado (o sin nadie que pueda entrar):
  # primero se crea el administrador.
  def exigir_instalacion
    redirect_to instalar_path if Usuario.activos.none?
  end

  # Un módulo apagado no existe: sus pantallas lo dicen en vez de dar un 404 pelón.
  def exigir_modulo
    apagado = modulos_requeridos.find { |m| !Modulo.activo?(m) } or return
    render "errores/modulo_apagado", status: :not_found, locals: { modulo: apagado }
  end

  def exigir_sesion
    redirect_to entrar_path, alert: t("sesion.inicia_para_continuar") unless usuario_actual
  end

  def puede?(clave)
    usuario_actual&.puede?(clave) || false
  end

  # Corta la petición si el usuario no tiene el permiso.
  def autorizar!(clave)
    raise SinPermiso, clave unless puede?(clave)
  end

  # Autorización diferida (no hay PIN): si quien opera tiene el permiso, queda a su nombre; si no,
  # la operación sigue igual y queda por revisar (ver Revision). Devuelve quien autoriza o nil.
  def autorizador_o_revision(clave)
    puede?(clave) ? usuario_actual : nil
  end

  # Deja la operación en la bandeja de revisión si nadie la autorizó.
  def revisar_si_hace_falta(registro, autoriza, motivo:, valor_centavos: 0, sucursal: sucursal_actual)
    return if autoriza
    Revision.abrir!(registro, usuario: usuario_actual, sucursal: sucursal, motivo: motivo, valor_centavos: valor_centavos)
  end

  def iniciar_sesion(usuario)
    cookies.signed.permanent[:usuario_id] = { value: usuario.id, httponly: true, same_site: :lax }
    Current.usuario = usuario
  end

  def cerrar_sesion
    cookies.delete(:usuario_id)
    Current.reset
  end
end
