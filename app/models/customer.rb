# A customer of the business. On its own it is a name with contact details; what matters is what
# hangs off it: their credit account and their orders.
class Customer < ApplicationRecord
  has_many :credit_movements, class_name: "CreditMovement", dependent: :restrict_with_error
  has_many :sales, dependent: :restrict_with_error
  has_many :account_payments, dependent: :restrict_with_error
  has_many :orders, dependent: :restrict_with_error
  has_many :returnable_movements, dependent: :restrict_with_error

  validates :name, presence: true
  validates :credit_limit_cents, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  # The credit type is a key declared in the credit rule; the cut-off day is a weekday (0 = Sunday).
  validates :cutoff_day, inclusion: { in: 0..6 }, allow_nil: true
  validate :credit_type_is_declared, if: :will_save_change_to_credit_type?

  normalizes :credit_type, with: ->(key) { key.to_s.strip.presence }

  scope :active, -> { where(active: true) }
  scope :with_credit_type, -> { where.not(credit_type: nil) }

  # The cut-off day the way the credit rule reads it: :monday … :sunday, or nil.
  def cutoff_keyword = cutoff_day && CreditRule::WEEKDAYS[cutoff_day]

  def credit_limit = BigDecimal(credit_limit_cents) / 100

  def credit_limit=(amount)
    self.credit_limit_cents = Money.cents(amount)
  end

  def account = CustomerAccount.new(self)
  def balance_cents = credit_movements.sum(:amount_cents)
  def returnable_account = ReturnableAccount.new(self)

  def to_s = name

  private

  # A type the rule stops declaring stays on the customer; only choosing an undeclared one is refused.
  def credit_type_is_declared
    errors.add(:credit_type, :inclusion) if credit_type.present? && !CreditRule.types.key?(credit_type)
  end
end
