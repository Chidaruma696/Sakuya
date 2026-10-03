# Lo común de los ganchos que deciden (el cierre de caja, el precio de un renglón…): la regla
# termina en (allow), (to-review motivo) o (reject motivo) y el núcleo hace lo que toque. Si la
# regla del negocio truena o no decide, decide la de fábrica y el error viaja en la decisión para
# que quede asentado.
#
# Cada gancho lo extiende y define DE_FABRICA, MOTIVOS (las palabras clave que sabe traducir),
# `funciones(datos)` con lo que la regla puede leer, `textos` (su sección de traducciones) y
# `interpolar(datos)` con lo que van a llevar sus motivos.
module Gancho
  Decision = Data.define(:veredicto, :motivo, :error) do
    def permite? = veredicto == :allow
    def revisar? = veredicto == :review
    def rechaza? = veredicto == :reject
  end

  def decidir_con(codigo, datos)
    return evaluar(self::DE_FABRICA, datos) if codigo.blank?
    evaluar(codigo, datos)
  rescue Lisp::Error => e
    evaluar(self::DE_FABRICA, datos).with(error: e.message)
  end

  # Evalúa un programa; levanta Lisp::Error si no termina en una decisión.
  def evaluar(codigo, datos)
    resultado = Lisp.ejecutar(codigo, funciones: funciones(datos).merge(decisiones(datos)))
    resultado.is_a?(Decision) ? resultado : raise(Lisp::Error, I18n.t("reglas.errores.sin_decision", valor: Lisp.a_texto(resultado)))
  end

  private

  def decisiones(datos)
    {
      "allow" => -> { Decision.new(veredicto: :allow, motivo: nil, error: nil) },
      "to-review" => ->(motivo) { Decision.new(veredicto: :review, motivo: motivo(motivo, datos), error: nil) },
      "reject" => ->(motivo) { Decision.new(veredicto: :reject, motivo: motivo(motivo, datos), error: nil) }
    }
  end

  def motivo(motivo, datos)
    case motivo
    when String then motivo.presence || raise(Lisp::Error, I18n.t("reglas.errores.motivo"))
    when Symbol
      raise Lisp::Error, I18n.t("reglas.errores.motivo_desconocido", motivo: motivo, motivos: self::MOTIVOS.join(" :")) unless self::MOTIVOS.include?(motivo)
      I18n.t("#{textos}.motivos.#{motivo.to_s.underscore}", **interpolar(datos))
    else raise Lisp::Error, I18n.t("reglas.errores.motivo")
    end
  end
end
