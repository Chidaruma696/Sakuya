class Payment < ApplicationRecord
  # The ways money comes in. Selling on account brings in no money: it is charged to the customer's account.
  PAYMENT_METHODS = %w[cash transfer deposit].freeze
  ON_ACCOUNT = "credit".freeze

  belongs_to :sale

  validates :payment_method, inclusion: { in: PAYMENT_METHODS + [ ON_ACCOUNT ] }
  validates :amount_cents, numericality: { only_integer: true, greater_than: 0 }
end
