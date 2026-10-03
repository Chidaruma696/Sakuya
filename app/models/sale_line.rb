class SaleLine < ApplicationRecord
  belongs_to :sale, inverse_of: :lines
  belongs_to :product
  belongs_to :authorized_by, class_name: "User", optional: true
  belongs_to :promotion, optional: true
  has_many :refund_lines, dependent: :restrict_with_error

  validates :quantity, numericality: { greater_than: 0 }
  validates :price_cents, :catalog_cents, :amount_cents, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  def refunded_quantity
    refund_lines.sum(:quantity)
  end

  def pending_quantity
    quantity - refunded_quantity
  end
end
