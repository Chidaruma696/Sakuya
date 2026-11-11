# What a returnable product releases when it is sold: a kind of container, the quantity on a
# ticket line from which it counts and, optionally, one piece per every how many units. Left
# blank, a line that reaches the quantity releases one piece, whatever its size (one crate per
# weighing); with it, one piece per every that many (one case per eight bottles).
class ProductReturnable < ApplicationRecord
  belongs_to :product, inverse_of: :returnables

  validates :kind, presence: true, uniqueness: { scope: :product_id }
  validates :from_quantity, numericality: { greater_than: 0 }
  validates :per_quantity, numericality: { greater_than: 0 }, allow_nil: true
  validate :kind_is_declared, if: :will_save_change_to_kind?

  normalizes :kind, with: ->(key) { key.to_s.strip.presence }

  # How many pieces a ticket line of that quantity releases.
  def pieces_for(quantity)
    quantity = BigDecimal(quantity.to_s)
    return 0 if quantity < from_quantity
    per_quantity ? (quantity / per_quantity).floor : 1
  end

  private

  # A kind the rule stops declaring stays on the product; only choosing an undeclared one is refused.
  def kind_is_declared
    errors.add(:kind, :inclusion) if kind.present? && !ReturnableRule.kinds.key?(kind)
  end
end
