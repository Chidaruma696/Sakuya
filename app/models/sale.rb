class Sale < ApplicationRecord
  belongs_to :customer, optional: true
  belongs_to :branch
  belongs_to :shift
  belongs_to :user
  has_many :lines, class_name: "SaleLine", dependent: :restrict_with_error, inverse_of: :sale
  has_many :payments, dependent: :restrict_with_error
  has_many :refunds, dependent: :restrict_with_error

  validates :folio, presence: true, uniqueness: { scope: :branch_id }
  validates :code, :key, presence: true, uniqueness: true
  validates :status, inclusion: { in: %w[paid refunded] }
  validates :total_cents, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  scope :recent, -> { order(created_at: :desc) }

  def paid? = status == "paid"

  # What was actually paid: payments minus change.
  def paid_cents
    payments.sum(:amount_cents) - change_cents
  end

  # What is left of the sale: the total minus what was refunded.
  def balance_cents
    total_cents - total_refunded_cents
  end

  # The ticket carries its own EAN-13 (prefix 09 + branch + sequence) for refunds.
  def self.search(text)
    find_by(code: Barcode.variants(text)) || find_by(folio: text.to_s.strip.upcase)
  end

  def total_refunded_cents
    refunds.sum(:total_cents)
  end

  def to_s
    folio
  end

  # Of what went on the customer's account, what has not yet been taken off for refunds.
  def on_account_pending_cents
    payments.where(payment_method: Payment::ON_ACCOUNT).sum(:amount_cents) - refunds.sum(:on_account_cents)
  end
end
