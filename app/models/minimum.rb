# A product's minimum and maximum at a branch, and what is needed to restock it.
class Minimum < ApplicationRecord
  belongs_to :branch
  belongs_to :product

  validates :minimum, numericality: { greater_than_or_equal_to: 0 }
  validates :maximum, numericality: { greater_than_or_equal_to: :minimum }, allow_nil: true
  validates :product_id, uniqueness: { scope: :branch_id }

  def cap = maximum || minimum

  # What a branch is short of: [[product, quantity]] for whatever is below its minimum, to reach
  # the maximum. Counts what is available (stock reserved for orders already has an owner). Whole
  # pieces are rounded up.
  def self.suggested(branch)
    stock_levels = StockLevel.where(branch: branch).pluck(:product_id, :quantity).to_h
    reserved = Reservations.by_product(branch)
    where(branch: branch).includes(:product).filter_map do |m|
      next unless m.product.active
      available = stock_levels.fetch(m.product_id, 0) - reserved.fetch(m.product_id, 0)
      next if available >= m.minimum
      missing = m.cap - available
      missing = missing.ceil unless m.product.fractional?
      [ m.product, missing.round(3) ] if missing.positive?
    end.sort_by { |p, _| p.name }
  end

  # Saves a branch's minimums in one go: { product_id => { minimum:, maximum: } }. A blank minimum
  # removes the row.
  def self.store!(branch, values)
    transaction do
      values.each do |product_id, v|
        row = find_or_initialize_by(branch: branch, product_id: product_id)
        if v[:minimum].blank?
          row.destroy if row.persisted?
          next
        end
        row.update!(minimum: v[:minimum], maximum: v[:maximum].presence)
      end
    end
  end
end
