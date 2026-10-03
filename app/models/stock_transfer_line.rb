class StockTransferLine < ApplicationRecord
  belongs_to :stock_transfer, inverse_of: :lines
  belongs_to :product

  validates :quantity, numericality: { greater_than: 0 }
  validates :boxes, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
end
