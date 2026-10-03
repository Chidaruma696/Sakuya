# El gancho del cierre de caja: un programa en el Lisp de Sakuya mira cómo salió el conteo y
# propone qué hacer con la diferencia. La regla solo lee y devuelve una decisión; quien cierra
# el corte es el controlador, por el camino de siempre.
#
# Contrato v1. Recibe, en pesos: (difference) contado − esperado (negativo = falta dinero),
# (counted), (expected), (float), (sales), (cash-sales), (returns), (withdrawals), (limit) el
# tope de Ajustes › Caja (0 = sin tope); además (tickets) y (authorized), que es verdadero si
# quien cierra tiene el permiso caja.diferencia. Devuelve (allow), (to-review motivo) o
# (reject motivo); el motivo es una cadena o una palabra clave de las que Sakuya traduce.
module ReglaCorte
  VERSION = 1

  DE_FABRICA = <<~LISP
    ; Closing the cash drawer. (difference) is counted minus expected: negative means missing money.
    ; Answer (allow), (to-review "why") or (reject "why").
    (if (or (= (limit) 0)
            (<= (abs (difference)) (limit))
            (authorized))
        (allow)
        (to-review :over-limit))
  LISP

  # Las palabras clave que el núcleo sabe decir en el idioma de quien cierra.
  MOTIVOS = %i[over-limit].freeze

  Decision = Data.define(:veredicto, :motivo, :error) do
    def permite? = veredicto == :allow
    def revisar? = veredicto == :review
    def rechaza? = veredicto == :reject
  end

  # Decide con la regla vigente (o la de fábrica). Si la del negocio truena, decide la de fábrica
  # y el error viaja en la decisión para que quede asentado.
  def self.decidir(corte, contado_centavos:, usuario:, codigo: Regla.vigente("corte")&.codigo)
    datos = Datos.new(corte, contado_centavos, usuario)
    return evaluar(DE_FABRICA, datos) if codigo.blank?
    evaluar(codigo, datos)
  rescue Lisp::Error => e
    evaluar(DE_FABRICA, datos).with(error: e.message)
  end

  # Evalúa un programa contra un conteo; levanta Lisp::Error si no devuelve una decisión.
  def self.evaluar(codigo, datos)
    resultado = Lisp.ejecutar(codigo, funciones: funciones(datos))
    resultado.is_a?(Decision) ? resultado : raise(Lisp::Error, I18n.t("regla_corte.errores.sin_decision", valor: Lisp.a_texto(resultado)))
  end

  def self.funciones(datos)
    {
      "difference" => -> { datos.pesos(datos.diferencia) },
      "counted" => -> { datos.pesos(datos.contado) },
      "expected" => -> { datos.pesos(datos.esperado) },
      "float" => -> { datos.pesos(datos.corte.fondo_centavos) },
      "sales" => -> { datos.pesos(datos.corte.total_ventas_centavos) },
      "cash-sales" => -> { datos.pesos(datos.corte.efectivo_ventas_centavos) },
      "returns" => -> { datos.pesos(datos.corte.devoluciones_centavos) },
      "withdrawals" => -> { datos.pesos(datos.corte.retiros_centavos) },
      "limit" => -> { datos.pesos(Corte.tope_diferencia_centavos) },
      "tickets" => -> { datos.corte.ventas.count },
      "authorized" => -> { datos.usuario.puede?("caja.diferencia") },
      "allow" => -> { Decision.new(veredicto: :allow, motivo: nil, error: nil) },
      "to-review" => ->(motivo) { Decision.new(veredicto: :review, motivo: motivo(motivo, datos), error: nil) },
      "reject" => ->(motivo) { Decision.new(veredicto: :reject, motivo: motivo(motivo, datos), error: nil) }
    }
  end

  def self.motivo(motivo, datos)
    case motivo
    when String then motivo.presence || raise(Lisp::Error, I18n.t("regla_corte.errores.motivo"))
    when Symbol
      raise Lisp::Error, I18n.t("regla_corte.errores.motivo_desconocido", motivo: motivo, motivos: MOTIVOS.join(" :")) unless MOTIVOS.include?(motivo)
      I18n.t("regla_corte.motivos.#{motivo.to_s.underscore}", diferencia: Dinero.pesos(datos.diferencia), tope: Dinero.pesos(Corte.tope_diferencia_centavos))
    else raise Lisp::Error, I18n.t("regla_corte.errores.motivo")
    end
  end

  private_class_method :funciones, :motivo

  # El conteo que se está cerrando, en centavos; el programa lo lee en pesos.
  Datos = Struct.new(:corte, :contado, :usuario) do
    def esperado = @esperado ||= corte.efectivo_esperado_centavos
    def diferencia = contado - esperado
    def pesos(centavos) = BigDecimal(centavos.to_i) / 100
  end
end
