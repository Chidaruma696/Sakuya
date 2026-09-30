class Existencia < ApplicationRecord
  belongs_to :sucursal
  belongs_to :producto

  validates :cantidad, numericality: { greater_than_or_equal_to: 0 }

  def self.de(sucursal, producto)
    find_by(sucursal: sucursal, producto: producto)&.cantidad || BigDecimal("0")
  end
end
