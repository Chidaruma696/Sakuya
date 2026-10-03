class StockLevel < ApplicationRecord
  belongs_to :branch
  belongs_to :product

  validates :quantity, numericality: { greater_than_or_equal_to: 0 }

  def self.quantity_for(branch, product)
    find_by(branch: branch, product: product)&.quantity || BigDecimal("0")
  end
end
