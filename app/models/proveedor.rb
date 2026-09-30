# Quien nos surte. El saldo (lo que le debemos) sale siempre de su libro (movimientos_proveedor),
# nunca de una columna.
class Proveedor < ApplicationRecord
  self.table_name = "proveedores"

  has_many :facturas, class_name: "FacturaProveedor", dependent: :restrict_with_error
  has_many :recepciones, dependent: :restrict_with_error
  has_many :movimientos, class_name: "MovimientoProveedor", dependent: :restrict_with_error
  has_many :pagos, class_name: "PagoProveedor", dependent: :restrict_with_error

  validates :nombre, presence: true, uniqueness: { case_sensitive: false }
  validates :dias_credito, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  scope :activos, -> { where(activo: true) }

  def saldo_centavos = movimientos.sum(:delta_centavos)

  def to_s = nombre
end
