# Los idiomas de la interfaz: los tres de fábrica más los que traigan los plugins encendidos.
module Idiomas
  BASE = %w[es en de].freeze

  def self.todos = BASE + (de_plugins.keys - BASE)

  # { "fr" => "Français" } de los plugins encendidos.
  def self.de_plugins
    @de_plugins ||= {}
  end

  def self.nombre(codigo) = I18n.t("ajustes.idiomas.#{codigo}", default: de_plugins[codigo] || codigo)

  # Pone al día los textos de los plugins y los idiomas disponibles si algún plugin cambió. Barato:
  # una consulta por petición.
  def self.sincronizar!
    clave = Plugin.pick(Arel.sql("COUNT(*)"), Arel.sql("MAX(updated_at)"))
    return if clave == @clave
    traducciones = Plugin.activos.flat_map { |p| (p.leido.traducciones rescue []) }
    @de_plugins = traducciones.to_h { |t| [ t.idioma, t.nombre ] }
    # Primero los idiomas: I18n no guarda textos de un idioma que no está disponible.
    I18n.available_locales = todos.map(&:to_sym)
    TraduccionesPlugins::BACKEND.recargar!(traducciones.map { |t| [ t.idioma, t.textos ] })
    @clave = clave
  end
end
