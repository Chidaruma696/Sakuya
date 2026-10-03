class BranchPrice < ApplicationRecord
  self.table_name = "branch_prices"

  belongs_to :product
  belongs_to :branch

  validates :price_cents, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :branch_id, uniqueness: { scope: :product_id }
end
