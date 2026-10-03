# The texts plugins bring (translation …) take precedence over the YAML files: that way a plugin
# can add a whole language or change a text in one that already exists. Whatever a new language
# does not bring falls back to English, the default language. The texts are loaded from Languages.sync!.
module PluginTranslations
  class Backend < I18n::Backend::Simple
    # translations: [[language, { "key.with.dots" => "text" }], …]
    def reload!(translations)
      @translations = Concurrent::Hash.new
      translations.each do |language, texts|
        texts.each { |key, text| store_translations(language, key.split(".").reverse.reduce(text) { |leaf, part| { part => leaf } }) }
      end
      @initialized = true
    end

    def initialized? = true
    def load_translations(*) = nil
  end

  BACKEND = Backend.new
end

Rails.application.config.after_initialize do
  I18n.backend = I18n::Backend::Chain.new(PluginTranslations::BACKEND, I18n.backend) unless I18n.backend.is_a?(I18n::Backend::Chain)
end
