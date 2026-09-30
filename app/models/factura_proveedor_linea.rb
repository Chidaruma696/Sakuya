class FacturaProveedorLinea < ApplicationRecord
  belongs_to :factura, class_name: "FacturaProveedor", foreign_key: :factura_proveedor_id, inverse_of: :lineas
  belongs_to :producto

  validates :cantidad, numericality: { greater_than: 0 }
  validates :precio_centavos, numericality: { only_integer: true, greater_than: 0 }
  validates :cajas, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  before_validation { self.importe_centavos = Dinero.importe(cantidad, precio_centavos) if cantidad && precio_centavos }
end
