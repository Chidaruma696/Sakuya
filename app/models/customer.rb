# A customer of the business. On its own it is a name with contact details; what matters is what
# hangs off it: their credit account and their orders.
class Customer < ApplicationRecord
  has_many :credit_movements, class_name: "CreditMovement", dependent: :restrict_with_error
  has_many :sales, dependent: :restrict_with_error
  has_many :account_payments, dependent: :restrict_with_error
  has_many :orders, dependent: :restrict_with_error

  validates :name, presence: true
  validates :credit_limit_cents, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  scope :active, -> { where(active: true) }

  def credit_limit = BigDecimal(credit_limit_cents) / 100

  def credit_limit=(amount)
    self.credit_limit_cents = Money.cents(amount)
  end

  def account = CustomerAccount.new(self)
  def balance_cents = credit_movements.sum(:amount_cents)

  def to_s = name
end
