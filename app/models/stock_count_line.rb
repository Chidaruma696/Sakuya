class StockCountLine < ApplicationRecord
  belongs_to :stock_count, inverse_of: :lines
  belongs_to :product

  def counted
    scanned + manual
  end
end
