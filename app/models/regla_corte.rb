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
    ; Out of the limit it stops: only someone allowed to accept differences can close, and it goes to review.
    (if (or (= (limit) 0)
            (<= (abs (difference)) (limit)))
        (allow)
        (reject :over-limit))
  LISP

  # Las palabras clave que el núcleo sabe decir en el idioma de quien cierra.
  MOTIVOS = %i[over-limit].freeze

  extend Gancho

  CASO = "reglas/caso_corte".freeze # el caso de prueba del editor

  # Decide con la regla vigente (o la de fábrica).
  def self.decidir(corte, contado_centavos:, usuario:, codigo: Regla.vigente("corte")&.codigo)
    decidir_con(codigo, Datos.new(corte, contado_centavos, usuario))
  end

  def self.textos = "regla_corte"

  def self.interpolar(datos)
    { diferencia: Dinero.pesos(datos.diferencia), tope: Dinero.pesos(Corte.tope_diferencia_centavos) }
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
      "authorized" => -> { datos.autorizado? }
    }
  end

  private_class_method :funciones, :interpolar, :textos

  # El conteo que se está cerrando, en centavos; el programa lo lee en pesos. Para probar en el
  # editor, `autorizado` dice a mano si quien cierra tiene permiso.
  class Datos
    attr_reader :corte, :contado

    def initialize(corte, contado, usuario = nil, autorizado: nil)
      @corte = corte
      @contado = contado.to_i
      @usuario = usuario
      @autorizado = autorizado
    end

    def esperado = @esperado ||= corte.efectivo_esperado_centavos
    def diferencia = contado - esperado
    def autorizado? = @autorizado.nil? ? @usuario.puede?("caja.diferencia") : @autorizado
    def pesos(centavos) = BigDecimal(centavos.to_i) / 100
  end

  # El caso de prueba del editor: lo que se espera en la gaveta (de entrada, lo del corte abierto),
  # lo que se contó y si cierra alguien con permiso.
  def self.caso(params, sucursal)
    esperado = params[:esperado].present? ? Dinero.centavos(params[:esperado]) : (Corte.abierto_en(sucursal)&.efectivo_esperado_centavos || 50_000)
    contado = params[:contado].present? ? Dinero.centavos(params[:contado]) : esperado
    { esperado: esperado, contado: contado, autorizado: params[:autorizado] == "1" }
  end

  # Un cierre de mentira: un corte sin guardar con ese fondo y sin ventas. No toca la base.
  def self.probar(codigo, caso)
    evaluar(codigo, Datos.new(Corte.new(fondo_centavos: caso[:esperado]), caso[:contado], autorizado: caso[:autorizado]))
  end

  FUNCIONES = %w[difference counted expected float sales cash-sales returns withdrawals limit tickets authorized].freeze
  EJEMPLO = <<~LISP
    (cond ((> (difference) 0) (to-review "Extra money"))
          ((< (difference) -200) (reject :over-limit))
          (else (allow)))
  LISP
end
