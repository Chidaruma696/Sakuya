# Los textos que traen los plugins (translation …) van por delante de los YAML: así un plugin
# puede añadir un idioma entero o cambiar un texto de uno que ya existe. Lo que un idioma nuevo
# no traiga cae al español, como siempre. Los textos se cargan desde Idiomas.sincronizar!.
module TraduccionesPlugins
  class Backend < I18n::Backend::Simple
    # traducciones: [[idioma, { "clave.con.puntos" => "texto" }], …]
    def recargar!(traducciones)
      @translations = Concurrent::Hash.new
      traducciones.each do |idioma, textos|
        textos.each { |clave, texto| store_translations(idioma, clave.split(".").reverse.reduce(texto) { |hoja, parte| { parte => hoja } }) }
      end
      @initialized = true
    end

    def initialized? = true
    def load_translations(*) = nil
  end

  BACKEND = Backend.new
end

Rails.application.config.after_initialize do
  I18n.backend = I18n::Backend::Chain.new(TraduccionesPlugins::BACKEND, I18n.backend) unless I18n.backend.is_a?(I18n::Backend::Chain)
end
