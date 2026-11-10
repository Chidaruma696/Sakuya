class ReceiptLine < ApplicationRecord
  belongs_to :receipt, inverse_of: :lines
  belongs_to :product

  validates :quantity, numericality: { greater_than: 0 }
  validate { errors.add(:quantity, I18n.t("errors.till.whole_pieces", product: product.name)) if product && !product.fractional? && quantity.to_d != quantity.to_d.floor }
  validates :boxes, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
end
