class Sucursal < ApplicationRecord
  # matriz: la oficina central, de donde sale todo. tienda: vende. almacen: bodega donde la
  # mercancía solo se guarda: sin caja ni conteos; entra y sale por traspasos, y solo va a la matriz.
  TIPOS = %w[matriz tienda almacen].freeze

  has_many :usuarios, dependent: :restrict_with_error
  has_many :folios, dependent: :destroy
  has_many :existencias, dependent: :restrict_with_error
  has_many :cortes, dependent: :restrict_with_error
  has_many :ventas, dependent: :restrict_with_error

  validates :limite_efectivo_centavos, numericality: { only_integer: true, greater_than: 0 }
  # Cada cuántos días toca un conteo; vacío = sin aviso.
  validates :dias_conteo, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true

  validates :codigo, presence: true, uniqueness: true, length: { maximum: 10 }
  validates :nombre, presence: true
  validates :tipo, inclusion: { in: TIPOS }

  scope :activas, -> { where(activa: true) }

  def self.matriz
    find_by(tipo: "matriz")
  end

  def matriz?
    tipo == "matriz"
  end

  def almacen? = tipo == "almacen"

  def caja? = !almacen?

  scope :con_caja, -> { where.not(tipo: "almacen") }
  scope :almacenes, -> { where(tipo: "almacen") }

  def limite_efectivo
    BigDecimal(limite_efectivo_centavos) / 100
  end

  def to_s
    nombre
  end
end
