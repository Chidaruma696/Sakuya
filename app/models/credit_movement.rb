# A line in the customer's account. Insert only: the balance is the sum of the signed amounts
# (a charge adds; an account payment or a refund subtracts).
class CreditMovement < ApplicationRecord
  self.table_name = "credit_movements"
  KINDS = %w[charge account_payment refund].freeze

  belongs_to :customer
  belongs_to :branch
  belongs_to :user
  belongs_to :reference, polymorphic: true, optional: true

  validates :kind, inclusion: { in: KINDS }
  validates :date, presence: true
  validates :amount_cents, numericality: { only_integer: true, other_than: 0 }
  validate { errors.add(:amount_cents, :invalid) if (kind == "charge") != amount_cents.to_i.positive? }

  before_update { raise ActiveRecord::ReadOnlyRecord, "the customer account cannot be edited" }
  before_destroy { raise ActiveRecord::ReadOnlyRecord, "the customer account cannot be deleted" }

  scope :in_order, -> { order(:date, :id) }
end
