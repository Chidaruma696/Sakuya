class PrecioSucursal < ApplicationRecord
  self.table_name = "precios_sucursal"

  belongs_to :producto
  belongs_to :sucursal

  validates :precio_centavos, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :sucursal_id, uniqueness: { scope: :producto_id }
end
