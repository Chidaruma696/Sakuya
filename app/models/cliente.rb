# Un cliente del negocio. Por sí solo es un nombre con datos de contacto; lo que importa es lo que
# cuelga de él: su cuenta de crédito y sus pedidos.
class Cliente < ApplicationRecord
  has_many :movimientos_credito, class_name: "MovimientoCredito", dependent: :restrict_with_error
  has_many :ventas, dependent: :restrict_with_error
  has_many :abonos, dependent: :restrict_with_error

  validates :nombre, presence: true
  validates :limite_credito_centavos, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  scope :activos, -> { where(activo: true) }

  def limite_credito = BigDecimal(limite_credito_centavos) / 100

  def limite_credito=(pesos)
    self.limite_credito_centavos = Dinero.centavos(pesos)
  end

  def cuenta = CuentaCliente.new(self)
  def saldo_centavos = movimientos_credito.sum(:monto_centavos)

  def to_s = nombre
end
