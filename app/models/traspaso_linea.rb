class TraspasoLinea < ApplicationRecord
  belongs_to :traspaso, inverse_of: :lineas
  belongs_to :producto

  validates :cantidad, numericality: { greater_than: 0 }
  validates :cajas, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
end
