# Un plugin en Lisp: un archivo que el negocio instala para traer lo que Sakuya no trae. Solo
# declara; al instalarlo se lee, nunca se ejecuta. Puede traer:
#
#   (plugin "fonda" (name "Fonda") (version "1.0") (author "…") (description "…"))
#   (define (fonda/margin sales returns) (- sales returns))   ; funciones para todas las reglas
#   (report "Ventas de la semana" (sales (days-ago 7) (today))) ; informes para el REPL
#   (translation "fr" "Français" ("caja.cobrar" "Encaisser"))   ; un idioma para la interfaz
#
# Las funciones llevan el prefijo del plugin ("fonda/…"), así que no pisan las de Sakuya ni las de
# otro plugin. Un plugin apagado no aporta nada.
class Plugin < ApplicationRecord
  self.table_name = "plugins"
  IDENTIFICADOR = /\A[a-z][a-z0-9-]{1,30}\z/
  IDIOMA = /\A[a-z]{2}(-[A-Z]{2})?\z/
  DATOS = %w[name version author description].freeze
  EJEMPLO = <<~LISP
    ; fonda.lisp: a Sakuya plugin. It only declares; nothing runs when it is installed.
    (plugin "fonda"
      (name "Fonda")
      (version "1.0")
      (author "Someone")
      (description "Helpers for a small eatery"))

    ; Functions for every rule, the dashboard and the REPL. They carry the plugin prefix.
    (define (fonda/big-discount? limit) (> (discount) limit))

    ; Saved questions for the REPL.
    (report "Sales of the week" (sum-of :total (sales (days-ago 7) (today))))

    ; A language for the interface; whatever it does not translate stays in Spanish.
    (translation "fr" "Français"
      ("caja.cobrar" "Encaisser")
      ("cinta.pestanas.caja" "Caisse"))
  LISP
  EJEMPLO.freeze

  belongs_to :usuario

  validates :identificador, presence: true, uniqueness: true, format: { with: IDENTIFICADOR }
  validates :nombre, :codigo, presence: true

  scope :activos, -> { where(activo: true).order(:identificador) }

  Leido = Data.define(:identificador, :datos, :funciones, :informes, :traducciones)
  Informe = Data.define(:plugin, :titulo, :codigo)
  Traduccion = Data.define(:idioma, :nombre, :textos)

  # Lee un archivo de plugin y revisa todo lo que trae; levanta Lisp::Error con lo que falla.
  def self.leer(texto)
    formas = Lisp::Lector.leer(texto.to_s)
    cabeza = formas.first
    unless cabeza.is_a?(Array) && cabeza.first == Lisp::Simbolo.new("plugin") && cabeza[1].is_a?(String)
      raise Lisp::Error, I18n.t("plugins.errores.cabecera")
    end
    id = cabeza[1]
    raise Lisp::Error, I18n.t("plugins.errores.identificador", id: id) unless id.match?(IDENTIFICADOR)
    datos = cabeza.drop(2).to_h do |par|
      unless par.is_a?(Array) && par.size == 2 && par.first.is_a?(Lisp::Simbolo) && DATOS.include?(par.first.nombre) && par.last.is_a?(String)
        raise Lisp::Error, I18n.t("plugins.errores.dato", dato: Lisp.a_texto(par), datos: DATOS.join(", "))
      end
      [ par.first.nombre, par.last ]
    end
    funciones = []
    informes = []
    traducciones = []
    formas.drop(1).each do |forma|
      case forma.is_a?(Array) && forma.first.is_a?(Lisp::Simbolo) ? forma.first.nombre : nil
      when "define" then funciones << revisar_define!(forma, id)
      when "report" then informes << revisar_informe!(forma, id)
      when "translation" then traducciones << revisar_traduccion!(forma)
      else raise Lisp::Error, I18n.t("plugins.errores.forma", forma: Lisp.a_texto(forma).truncate(60))
      end
    end
    Leido.new(identificador: id, datos: datos, funciones: funciones, informes: informes, traducciones: traducciones)
  end

  # Solo (define (prefijo/nombre args…) cuerpo…) o (define prefijo/nombre valor).
  def self.revisar_define!(forma, id)
    destino = forma[1]
    nombre = (destino.is_a?(Array) ? destino.first : destino)
    unless nombre.is_a?(Lisp::Simbolo) && nombre.nombre.start_with?("#{id}/") && forma.size >= 3
      raise Lisp::Error, I18n.t("plugins.errores.prefijo", nombre: Lisp.a_texto(nombre), id: id)
    end
    forma
  end

  def self.revisar_informe!(forma, id)
    unless forma.size == 3 && forma[1].is_a?(String)
      raise Lisp::Error, I18n.t("plugins.errores.informe")
    end
    Informe.new(plugin: id, titulo: forma[1], codigo: Lisp.a_texto(forma[2]))
  end

  def self.revisar_traduccion!(forma)
    idioma, nombre, *pares = forma.drop(1)
    unless idioma.is_a?(String) && idioma.match?(IDIOMA) && nombre.is_a?(String)
      raise Lisp::Error, I18n.t("plugins.errores.traduccion")
    end
    textos = pares.to_h do |par|
      raise Lisp::Error, I18n.t("plugins.errores.par", par: Lisp.a_texto(par).truncate(60)) unless par.is_a?(Array) && par.size == 2 && par.all?(String)
      par
    end
    # Las claves *_html se pintan sin escapar: un plugin no las toca.
    html = textos.keys.select { |clave| clave.end_with?("_html") || clave.split(".").last == "html" }
    raise Lisp::Error, I18n.t("plugins.errores.html", claves: html.first(5).join(", ")) if html.any?
    desconocidas = textos.keys.reject { |clave| I18n.exists?(clave, locale: :es) }
    raise Lisp::Error, I18n.t("plugins.errores.claves", claves: desconocidas.first(5).join(", ")) if desconocidas.any?
    Traduccion.new(idioma: idioma, nombre: nombre, textos: textos)
  end

  private_class_method :revisar_define!, :revisar_informe!, :revisar_traduccion!

  # Instala (o pone al día, si ya estaba) un plugin desde su archivo. Uno nuevo llega apagado.
  def self.instalar!(texto, usuario:)
    leido = leer(texto)
    plugin = find_or_initialize_by(identificador: leido.identificador)
    plugin.update!(nombre: leido.datos["name"].presence || leido.identificador, version: leido.datos["version"], autor: leido.datos["author"],
                   descripcion: leido.datos["description"], codigo: texto, usuario: usuario)
    plugin
  end

  def leido = @leido ||= self.class.leer(codigo)

  # Las funciones de los plugins encendidos, ya leídas, para evaluarlas antes de cada programa.
  # Se cachean por la hora del último cambio a cualquier plugin.
  def self.preludio
    clave = pick(Arel.sql("COUNT(*)"), Arel.sql("MAX(updated_at)"))
    @preludio = nil if @clave_preludio != clave
    @clave_preludio = clave
    @preludio ||= activos.flat_map { |p| p.leido.funciones }.freeze
  end

  def self.informes = activos.flat_map { |p| p.leido.informes }

  def to_s = nombre
end
