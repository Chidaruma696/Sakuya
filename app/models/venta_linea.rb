class VentaLinea < ApplicationRecord
  belongs_to :venta, inverse_of: :lineas
  belongs_to :producto
  belongs_to :autorizado_por, class_name: "Usuario", optional: true
  belongs_to :promocion, optional: true
  has_many :devolucion_lineas, dependent: :restrict_with_error

  validates :cantidad, numericality: { greater_than: 0 }
  validates :precio_centavos, :catalogo_centavos, :importe_centavos, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  def cantidad_devuelta
    devolucion_lineas.sum(:cantidad)
  end

  def cantidad_pendiente
    cantidad - cantidad_devuelta
  end
end
