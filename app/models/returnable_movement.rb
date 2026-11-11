# A line in a customer's count of returnable containers. Insert only: the count of a kind is the
# sum of the signed quantities (pieces that leave add; pieces that come back or are written off
# subtract). Below zero the customer has pieces in their favor.
class ReturnableMovement < ApplicationRecord
  REASONS = %w[out back write_off entry].freeze

  belongs_to :customer
  belongs_to :branch
  belongs_to :user
  belongs_to :reference, polymorphic: true, optional: true

  validates :kind, presence: true
  validates :reason, inclusion: { in: REASONS }
  validates :date, presence: true
  validates :quantity, numericality: { only_integer: true, other_than: 0 }
  validate do
    errors.add(:quantity, :invalid) if reason == "out" && quantity.to_i.negative?
    errors.add(:quantity, :invalid) if %w[back write_off].include?(reason) && quantity.to_i.positive?
  end

  before_update { raise ActiveRecord::ReadOnlyRecord, "the returnables count cannot be edited" }
  before_destroy { raise ActiveRecord::ReadOnlyRecord, "the returnables count cannot be deleted" }

  scope :in_order, -> { order(:date, :id) }
end
