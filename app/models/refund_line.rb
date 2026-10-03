class RefundLine < ApplicationRecord
  belongs_to :refund, inverse_of: :lines
  belongs_to :sale_line

  validates :quantity, numericality: { greater_than: 0 }
  validates :amount_cents, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
end
