class OrderLine < ApplicationRecord
  belongs_to :order
  belongs_to :product

  validates :quantity, numericality: { greater_than: 0 }
  validate { errors.add(:quantity, I18n.t("errors.till.whole_pieces", product: product.name)) if product && !product.fractional? && quantity.to_d != quantity.to_d.floor }
end
