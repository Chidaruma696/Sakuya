# The interface languages: the three built-in ones plus whatever the active plugins bring.
module Languages
  BASE = %w[es en de].freeze

  def self.all = BASE + (from_plugins.keys - BASE)

  # { "fr" => "Français" } from the active plugins.
  def self.from_plugins
    @from_plugins ||= {}
  end

  def self.name(code) = I18n.t("settings.languages.#{code}", default: from_plugins[code] || code)

  # Refreshes the plugins' texts and the available languages if any plugin changed. Cheap: one
  # query per request.
  def self.sync!
    key = Plugin.pick(Arel.sql("COUNT(*)"), Arel.sql("MAX(updated_at)"))
    return if key == @key
    translations = Plugin.active.flat_map { |p| (p.parsed.translations rescue []) }
    @from_plugins = translations.to_h { |t| [ t.language, t.name ] }
    # Languages first: I18n does not store texts for a language that is not available.
    I18n.available_locales = all.map(&:to_sym)
    PluginTranslations::BACKEND.reload!(translations.map { |t| [ t.language, t.texts ] })
    @key = key
  end
end
