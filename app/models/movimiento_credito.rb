# Un renglón de la cuenta del cliente. Solo se inserta: el saldo es la suma de los montos con
# signo (cargo suma; abono y devolución restan).
class MovimientoCredito < ApplicationRecord
  self.table_name = "movimientos_credito"
  TIPOS = %w[cargo abono devolucion].freeze

  belongs_to :cliente
  belongs_to :sucursal
  belongs_to :usuario
  belongs_to :referencia, polymorphic: true, optional: true

  validates :tipo, inclusion: { in: TIPOS }
  validates :fecha, presence: true
  validates :monto_centavos, numericality: { only_integer: true, other_than: 0 }
  validate { errors.add(:monto_centavos, :invalid) if (tipo == "cargo") != monto_centavos.to_i.positive? }

  before_update { raise ActiveRecord::ReadOnlyRecord, "la cuenta del cliente no se edita" }
  before_destroy { raise ActiveRecord::ReadOnlyRecord, "la cuenta del cliente no se borra" }

  scope :en_orden, -> { order(:fecha, :id) }
end
