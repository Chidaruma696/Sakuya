# Corte de caja: abre con fondo, acumula lo que pasa por la gaveta y cierra contando.
class Corte < ApplicationRecord
  belongs_to :sucursal
  belongs_to :usuario
  belongs_to :cerrado_por, class_name: "Usuario", optional: true
  has_many :ventas, dependent: :restrict_with_error
  has_many :retiros, dependent: :restrict_with_error
  has_many :devoluciones, dependent: :restrict_with_error

  # { centavos => cuántos } de cómo se contó la gaveta al cerrar; vacío si solo se tecleó el total.
  serialize :desglose, coder: JSON

  before_validation :asignar_folio, on: :create

  validates :folio, presence: true, uniqueness: { scope: :sucursal_id }
  validates :estado, inclusion: { in: %w[abierto cerrado] }
  validates :fondo_centavos, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  scope :abiertos, -> { where(estado: "abierto") }

  def abierto? = estado == "abierto"

  def self.abierto_en(sucursal)
    abiertos.find_by(sucursal: sucursal)
  end

  # Billetes y monedas con que se cuenta la gaveta, en centavos y de mayor a menor (Ajustes › Caja).
  def self.denominaciones
    Ajuste["caja.denominaciones"].delete(" ").split(",").map { |d| Dinero.centavos(d) }.select(&:positive?).uniq.sort.reverse
  end

  # Diferencia (contado − esperado) a partir de la cual la regla de fábrica del corte pide motivo; 0 = sin tope.
  def self.tope_diferencia_centavos
    Ajuste.entero("caja.tope_diferencia") * 100
  end

  # Suma de un desglose { centavos => cuántos }; lo que no es denominación válida se ignora.
  def self.sumar(desglose)
    validas = denominaciones
    desglose.to_h.sum { |valor, cuantos| validas.include?(valor.to_i) ? valor.to_i * cuantos.to_i : 0 }
  end

  # Un corte abierto por sucursal.
  def self.abrir!(sucursal:, usuario:, fondo_centavos:)
    raise ArgumentError, I18n.t("errores.corte.sin_caja_en_almacen", sucursal: sucursal.nombre) unless sucursal.caja?
    raise ArgumentError, I18n.t("errores.corte.ya_abierto", sucursal: sucursal.nombre) if abierto_en(sucursal)
    create!(sucursal: sucursal, usuario: usuario, fondo_centavos: fondo_centavos, abierto_en: Time.current)
  end

  # Ventas cuyo dinero entró (cobradas o luego devueltas).
  def ventas_cobradas
    ventas
  end

  # Efectivo que entró por ventas: lo pagado en efectivo menos el cambio devuelto.
  def efectivo_ventas_centavos
    Pago.where(venta: ventas_cobradas, forma: "efectivo").sum(:monto_centavos) - ventas_cobradas.sum(:cambio_centavos)
  end

  def total_ventas_centavos
    ventas_cobradas.sum(:total_centavos)
  end

  def devoluciones_centavos
    devoluciones.sum(:total_centavos)
  end

  def retiros_centavos
    retiros.sum(:monto_centavos)
  end

  # Lo que debe haber en la gaveta ahora mismo.
  def efectivo_esperado_centavos
    fondo_centavos + efectivo_ventas_centavos - devoluciones_centavos - retiros_centavos
  end

  def excede_limite?
    efectivo_esperado_centavos > sucursal.limite_efectivo_centavos
  end

  def retirar!(monto_centavos:, motivo:, usuario:, autorizado_por: nil)
    comprobar_retiro!(monto_centavos, motivo)
    retiros.create!(monto_centavos: monto_centavos.to_i, motivo: motivo, usuario: usuario, autorizado_por: autorizado_por)
  end

  # Lo que un retiro necesita antes de preguntarle a nadie: corte abierto, motivo y efectivo.
  def comprobar_retiro!(monto_centavos, motivo)
    raise ArgumentError, I18n.t("errores.corte.cerrado") unless abierto?
    raise ArgumentError, I18n.t("errores.hace_falta_motivo") if motivo.blank?
    raise ArgumentError, I18n.t("errores.corte.sin_efectivo", monto: Dinero.pesos(efectivo_esperado_centavos)) if monto_centavos.to_i > efectivo_esperado_centavos
  end

  # Cierra contando: con el desglose por denominación (y el total sale de ahí) o con el total tecleado.
  def cerrar!(contado_centavos: nil, usuario:, desglose: nil)
    raise ArgumentError, I18n.t("errores.corte.ya_cerrado") unless abierto?
    validas = self.class.denominaciones
    limpio = desglose.to_h.to_h { |v, c| [ v.to_i, c.to_i ] }.select { |v, c| validas.include?(v) && c.positive? }
    contado = limpio.any? ? self.class.sumar(limpio) : contado_centavos.to_i
    esperado = efectivo_esperado_centavos
    update!(estado: "cerrado", contado_centavos: contado, esperado_centavos: esperado, desglose: limpio.presence,
            diferencia_centavos: contado - esperado, cerrado_en: Time.current, cerrado_por: usuario)
  end

  # "3 × $500, 8 × $100", para enseñar cómo se contó.
  def desglose_texto
    (desglose || {}).sort_by { |v, _| -v.to_i }.map { |v, c| "#{c} × #{Dinero.pesos(v.to_i)}" }.join(", ")
  end

  def to_s
    folio
  end

  private

  def asignar_folio
    self.folio ||= Folio.siguiente!(sucursal, "corte") if sucursal
  end
end
