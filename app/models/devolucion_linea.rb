class DevolucionLinea < ApplicationRecord
  belongs_to :devolucion, inverse_of: :lineas
  belongs_to :venta_linea

  validates :cantidad, numericality: { greater_than: 0 }
  validates :importe_centavos, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
end
